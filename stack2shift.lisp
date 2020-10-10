;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: STACK2SHIFT; Base: 10 -*-
;;;
;;; Copyright (C) 2020  Anthony Green <green@redhat.com>
;;;
;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU Affero General Public License
;;; as published by the Free Software Foundation, either version 3 of
;;; the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

(in-package :stack2shift)

(defparameter auth-vars
  '(("OS_USERNAME" . "admin")
    ("OS_AUTH_URL" . "YOUR-URL")
    ("OS_PASSWORD" . "YOUR-PASSWORD")
    ("OS_PROJECT_DOMAIN_NAME" . "Default")
    ("OS_PROJECT_NAME" . "admin")
    ("OS_USER_DOMAIN_NAME" . "Default")))

(defvar *openstack-vm-template*
  (alexandria:read-file-into-string "openstack-vm.yml.clt" :external-format :utf-8))

;; Set authentication environment variables
(dolist (v auth-vars)
  (setf (uiop:getenv (car v)) (cdr v)))

(defun glog (string &rest args)
  (apply #'format t string args)
  (format t "~%"))

(defun get-server-list ()
  (json:decode-json-from-string
   (uiop:run-program "openstack server list --format json"
                     :output '(:string :stripped t))))

(defun enumerate-option (stream arg ig nore)
  (declare (ignore ig))
  (declare (ignore nore))
  (format stream "~A ~A off"
          (cdr (assoc :+ID+ arg))
          (cdr (assoc :*NAME arg))))

(defun create-snapshot-from-volume (vm-name volume-id)
  (glog "Creating snapshot from volume ~A" volume-id)
  (let* ((snapshot-info (json:decode-json-from-string
                         (uiop:run-program (format nil "openstack volume snapshot create -f json --force --volume ~A ~A" volume-id vm-name)
                                           :output '(:string :stripped t))))
         (snapshot-id (cdr (assoc :ID snapshot-info))))
    (loop
      until (string= "available"
                     (cdr (assoc :STATUS
                                 (json:decode-json-from-string
                                  (uiop:run-program (format nil "openstack volume snapshot show -f json ~A" snapshot-id)
                                                    :output '(:string :stripped t))))))
      do (progn
           (glog "    .... waiting for snapshot")
           (sleep 5)))
    snapshot-id))

(defun create-volume-from-snapshot (vm-name snapshot-id)
  (glog "Creating volume from snapshot ~A" snapshot-id)
  (let* ((volume-info (json:decode-json-from-string
                       (uiop:run-program (format nil "openstack volume create -f json --snapshot ~A ~A" snapshot-id vm-name)
                                         :output '(:string :stripped t))))
         (volume-id (cdr (assoc :ID volume-info))))
    (loop
      until (string= "available"
                     (cdr (assoc :STATUS
                                 (json:decode-json-from-string
                                  (uiop:run-program (format nil "openstack volume show -f json ~A" volume-id)
                                                    :output '(:string :stripped t))))))
      do (progn
           (glog "    .... waiting for volume")
           (sleep 5)))
    volume-id))

(defun get-table-value (key s)
  (let ((rstream (make-string-input-stream s))
        (value nil)
        (regex (format nil ".*~A.* (.*) " key)))
    (loop for line = (read-line rstream nil)
          while (and line (null value))
          do (multiple-value-bind (match values)
                 (ppcre:scan-to-strings regex line)
               (when match
                 (setf value (aref values 0)))))
    value))

(defun create-image-from-volume (vm-name volume-id)
  (glog "Creating image from volume ~A" volume-id)
  (let* ((image-info (uiop:run-program (format nil "cinder upload-to-image --disk-format qcow2 ~A ~A" volume-id vm-name)
                                        :output '(:string :stripped t)))
         (image-id (get-table-value "image_id" image-info)))
    (loop
      until (string= "active"
                     (cdr (assoc :STATUS
                                 (json:decode-json-from-string
                                  (uiop:run-program (format nil "openstack image show -f json ~A" image-id)
                                                    :output '(:string :stripped t))))))
      do (progn
           (glog "    .... waiting for image")
           (sleep 5)))
    image-id))


;; Macros to clean up resources in the event of normal or non-local
;; exits...

(defmacro with-snapshot ((snapshot-id vm-name id) &body body)
  `(let ((,snapshot-id (create-snapshot-from-volume ,vm-name ,id)))
     (unwind-protect (progn ,@body)
       (glog "Cleaning up snapshot ~A" ,snapshot-id)
       (uiop:run-program (format nil "openstack volume snapshot delete ~A" ,snapshot-id)))))

(defmacro with-volume ((volume-id vm-name id) &body body)
  `(let ((,volume-id (create-volume-from-snapshot ,vm-name ,id)))
     (unwind-protect (progn ,@body)
       (glog "Cleaning up volume ~A" ,volume-id)
       (uiop:run-program (format nil "openstack volume delete ~A" ,volume-id)))))

(defmacro with-image ((image-id vm-name id) &body body)
  `(let ((,image-id (create-image-from-volume ,vm-name ,id)))
     (unwind-protect (progn ,@body)
       (glog "Cleaning up image ~A" ,image-id)
       (uiop:run-program (format nil "openstack image delete ~A" ,image-id)))))

(defun migrate-vm (vm-id)
  (glog "****************************************************************")
  (glog "Migrating vm-id ~A" vm-id)
  (glog "****************************************************************")
  (let* ((vm-info (json:decode-json-from-string (uiop:run-program (format nil "openstack server show --format json ~A" vm-id)
                                                                  :output '(:string :stripped t))))
         (vm-state (cdr (assoc :|+OS-EXT-STS+:VM--STATE| vm-info)))
         (vm-name (format nil "openstack-~A-~A" (cdr (assoc :NAME vm-info)) (str:substring 0 7 vm-id)))
         (vm-volumes (cdr (assoc :VOLUMES--ATTACHED vm-info))))
    ;; Shut down the VM if required
    (unless (string= vm-state "stopped")
      (print "SHUTTING DOWN"))
    (glog "Found volumes ~A" vm-volumes)
    (multiple-value-bind (match ids)
        (ppcre:scan-to-strings ".*'(.*)'" vm-volumes)
      ;; Assume one volume per...
      (let* ((id (aref ids 0)))
        (with-snapshot (snapshot-id vm-name id)
          (with-volume (volume-id vm-name snapshot-id)
            (with-image (image-id vm-name volume-id)
              (glog "Downloading image from OpenStack...")
              (uiop:run-program (format nil "openstack image save --file ~A.qcow2 ~A" vm-name image-id))
              (glog "Uploading image to OpenShift...")
              ;; Assume 10Gi is good enough
              (uiop:run-program (format nil "virtctl image-upload pvc ~A-pvc --size=10Gi --image-path=./~A.qcow2" vm-name vm-name))
              (delete-file (format nil "~A.qcow2" vm-name))
              (glog "Creating OpenShift VM definition: ~A.yml" vm-name)
              (with-open-file (stream (format nil "~A.yml" vm-name)
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
                (format stream (funcall (cl-template:compile-template *openstack-vm-template*)
                                        (list :vm-name vm-name))))
              (glog "Creating OpenShift VM: ~A ..." vm-name)
              (uiop:run-program (format nil "oc create -f ~A.yml" vm-name)))))))
    (glog "Done.")))

(defun main (args)
  (declare (ignore args))
  (glog "Connecting to OpenStack...")
  (let* ((servers (get-server-list)))
    (let ((rstream (make-string-input-stream
                    (uiop:run-program (with-output-to-string (cmd)
                                        (format cmd "dialog --clear --backtitle 'OpenStack to OpenShift Migration Demo Tool' --title 'OpenStack to OpenShift' --checklist 'Select VMs to migrate to OpenShift Virtualization' 15 60 4 ~{ ~/stack2shift:enumerate-option/ ~} 2>&1 >/dev/tty"
                                                servers))
                                      :output :string
                                      :input :interactive
                                      :error-output nil
                                      :on-error nil))))
      (uiop:run-program "clear" :output :interactive)
      (loop for vm-id = (read-line rstream nil)
            while vm-id
            do (migrate-vm vm-id))))
  (sb-ext:quit))
