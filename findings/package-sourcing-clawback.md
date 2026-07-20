# Clawing the base/system layer back to Azure Linux

Once `cost=` replaced `priority=` to fix the `grub2-efi-x64-cdboot`
conflict, dnf5 stopped shadowing Fedora by repo priority and started
letting whichever repo has the newer NEVRA win. The real installed
package database on a built live ISO showed: **1,177 total, 60 from
Azure Linux, 1,100 from Fedora, 17 Microsoft/GitHub.** Kernel,
glibc, systemd, and NetworkManager were all Fedora builds.

## The mechanism: excludepkgs on Fedora only

`--setopt=Fedora.excludepkgs=<list>` (and matching for
`Fedora-updates`) removes specific package names from Fedora's
candidate pool before `cost=` ever gets a tie to break. No return to
`priority=` needed. Wired into both pipelines: `kiwi/config.sh`'s
`FEDORA_EXCLUDES` variable and the live kickstart's `repo
--excludepkgs=`.

## Three packages/families not safe to move back

**glibc.** `gtk4` (hard dep of `gnome-shell`) requires `GLIBC_2.43`
that AZL4's glibc doesn't provide. The whole glibc family stays on
Fedora.

**wpa_supplicant.** No Azure Linux build exists at all. Excluding it
from Fedora with `--skip-unavailable` silently drops it - would break
WiFi with nothing in the build log to flag it. Caught by listing the
resulting offline repo's actual contents, not by trusting exit codes.

**fwupd/fwupd-efi.** AZL4's `fwupd` links against `libcbor.so.0.12`.
Fedora's `freerdp-libs` (a `gnome-connections` dependency) needs
`libcbor.so.0.13`. Only one can be installed. Fedora's `fwupd` is
functionally equivalent, so `fwupd` stays on Fedora. (`fwupd-efi`
still naturally resolves to AZL since Fedora doesn't ship it.)

## Version-locked sibling libraries

Clawing back a parent without its exact-version-locked siblings breaks
it:

- `util-linux`/`util-linux-core` → `libblkid`, `libmount`, `libuuid`,
  `libfdisk`, `libsmartcols`
- `e2fsprogs` → `libcom_err`
- `xz` → `xz-libs`

Confirmed ABI-compatible in both directions (identical max exported
symbol versions). Not the same as `fuse3-libs`, which is a genuine
soname fork (`libfuse3.so.3` vs `.so.4`) - both builds stay installed
side by side, each serving real consumers.

## The final list: 93 packages

```
audit, audit-libs, audit-rules, bash, bluez, bluez-libs, bluez-obexd,
bzip2, ca-certificates, chrony, coreutils, coreutils-common, cryptsetup,
cryptsetup-libs, dbus, dbus-broker, dbus-common, dbus-libs,
device-mapper, device-mapper-event, device-mapper-event-libs,
device-mapper-libs, device-mapper-persistent-data, diffutils,
dosfstools, e2fsprogs, e2fsprogs-libs, efibootmgr, findutils,
firewalld, gawk, grep, gzip, hwdata, iproute, iputils, kbd, kernel,
kernel-core, kernel-modules, kernel-modules-core, kernel-modules-extra,
kmod, less, libaio, libblkid, libcom_err, libfdisk, libmount, libnm,
libsmartcols, libuuid, linux-firmware, linux-firmware-whence, lvm2,
microcode_ctl, ModemManager-glib, mtools, ncurses, ncurses-base,
ncurses-libs, NetworkManager, NetworkManager-libnm, NetworkManager-team,
NetworkManager-tui, NetworkManager-wifi, openssh, openssh-clients,
openssh-server, patch, polkit, polkit-libs, procps-ng, sed,
selinux-policy, selinux-policy-targeted, setup, shadow-utils, sudo,
systemd, systemd-boot-unsigned, systemd-container, systemd-libs,
systemd-networkd, systemd-pam, systemd-resolved, systemd-udev, tar,
util-linux, util-linux-core, vim-minimal, xz, xz-libs
```

## Verification

Ran a real `dnf5 install --installroot` (via the rewritten
`scripts/podman-test-azl4-fedora.sh`, which now parses the live
kickstart directly instead of maintaining a second driftable copy)
against the full ~120-package live `%packages` list.

Result: **171 Azure Linux, 986 Fedora, 16 Microsoft/GitHub-or-other,
1,173 total** - up from 60/1,100/17. Kernel, systemd, NetworkManager,
bluez, linux-firmware, microcode_ctl, and the base coreutils/util-linux/
cryptsetup/openssh/audit/firewalld/selinux-policy layer all resolve to
Azure Linux. `glibc`, `wpa_supplicant`, `fwupd`, and the GNOME/GTK
stack stay on Fedora for the reasons above.

## What this doesn't fix, on purpose

Most packages by raw count are still Fedora, because a full GNOME
desktop is several hundred GUI/toolkit packages only Fedora builds.
What changed is which layer sits *underneath*: the kernel, init system,
network stack, and core userland are Azure Linux's own builds again.

## Follow-up: persisting every real upstream repo

The seven non-AZL, non-Fedora `repo` lines were build-time-only, never
persisted to `/etc/yum.repos.d`. Fixed with two new `.repo` files in
both `%post` blocks:

- `azl-desktop-microsoft-github.repo` (priority=1): `ms-prod`, `vscode`,
  `edge-canary`, `gh-cli`, `github-desktop`.
- `azl-desktop-rpmfusion.repo` (priority=50): `rpmfusion-free`,
  `rpmfusion-nonfree`.

Applies identically to the installer ISO via `kiwi/config.sh`.
