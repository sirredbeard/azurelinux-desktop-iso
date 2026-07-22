# Azure kernel USB HID module path

The Azure Linux x86_64 kernel used by this project does not include
`usbhid`. QEMU's USB tablet has nowhere to go. The same Azure userspace works
when the kernel and initramfs are replaced with the Fedora control kernel.
That was the useful comparison.

This is not a general input-driver project. The QEMU path uses USB tablet
input, so `usbhid` is the one module we need. `psmouse` is not part of this.

## The RPM

`azurelinux-desktop-usbhid-kmod` is built for one Azure kernel release at a
time:

1. Read the current Azure kernel package metadata.
2. Install its exact `kernel-devel` package in an Azure Linux container.
3. Download the matching Azure kernel source.
4. Turn on `CONFIG_USB_HID=m`.
5. Build `drivers/hid/usbhid`.
6. Check vermagic and package it with an exact `kernel-core-uname-r`
   requirement.

That last part matters. This is not a driver that can be carried forward by
force. Azure enables module versioning. An older `usbhid` RPM cannot load into
a newer kernel, and pretending otherwise would just leave the user without a
mouse in a more confusing way.

## Keeping up with Azure

The public 4.0 kernel repository had builds on May 5, 7, 11, 12, 14, 19, and
28, then July 18. There is no useful calendar cadence here. It is event
driven.

The publisher checks package metadata every four hours. The normal check is
small and stops when Pages already has the current RPM. A new kernel starts
the Azure-container build and publishes that RPM with the older builds still
in the repository. A missing package or matching source should fail before
we spend time building anything.

DNF can select a matching newer kmod when one has been published. In the
small gap after an Azure kernel update, it must not force an older module into
the new kernel. It must keep the last kernel with a matching module bootable,
then move forward when the matching RPM arrives.

The installed `azurelinux-desktop-policy` package makes that pairing
real. It requires one exact kernel and one exact `usbhid` RPM. A kernel-only
update stays out of the transaction while the old policy is installed. When
the publisher adds a newer policy, DNF can install the new kernel, policy,
and driver together.

The policy package has a general name because it may cover more than input in
the future. The Pages publisher drops the superseded package from repository
deployments.

The hybrid container does not need a kernel module. It does need to prove
that DNF can resolve `kernel` and `azurelinux-desktop-usbhid-kmod` together.
That catches a stale Pages repo before an ISO build does.

## Secure Boot

This is a project-built module, not a module signed by Azure Linux's kernel
key. It is useful for the project test path where Secure Boot module
enforcement is not enabled. It is not a Secure Boot solution.

## Operational boundaries

The source tarball is checked against Azure Linux's published SHA-512 before
compiling. The build and canary test both prove DNF can select the matching
kernel, policy, and module. The module file and vermagic must match before an
image is allowed to consume the repository.

The canary cannot load a kernel module. It is a package-transaction check,
not a hardware-input test. The live image, VM, and installed target are the
places where the driver must ultimately be exercised.
