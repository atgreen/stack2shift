## stack2shift - a proof-of-concept OpenStack to OpenShift migration tool

This is a simple migration tool for bringing OpenStack-hosted VMs over
to OpenShift Virtualiztion.

stack2shift will talk to OpenStack, and present a selection of VMs to migrate:

![alt text](select-vm.png "OpenStack VM selector")

Once selected, it will perform the actual migration and run the VMs in OpenShift:

![alt text](migrate-vm.png "OpenStack to OpenShift migration")

This is not intended for real world use. It is just a proof of concept
to demonstrate some of activities required for successful migration of
simple VM workloads.

stack2shift was tested with Red Hat OpenStack Platform 16.1, and
OpenShift Container Platform 4.5.

### Licensing

Copyright (C) 2020 by Anthony Green

Paperless is provided under the terms of the GNU Affero General Public
License, version 3 or later.
