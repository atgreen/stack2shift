;;;; stack2shift.asd

(asdf:defsystem #:stack2shift
  :description "Demo OpenStack to OpenShift Virtualization migration"
  :author "Anthony Green <green@redhat.com>"
  :license "MIT"
  :depends-on (#:cl-json
	       #:inferior-shell
	       #:cl-ppcre
               #:cl-template
               #:alexandria
               #:str)
  :serial t
  :components ((:file "package")
               (:file "stack2shift")))
