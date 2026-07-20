# Building a bootable ISO and getting to bare metal

This picks up after the package-resolution work in `investigation.md`.
This file covers what it takes to turn a validated package list into
something that boots, and what happens after "boot it in a VM" succeeds.

## Validated package list (pre-GH-Actions)

Ran the complete `kickstart/azurelinux-desktop.ks` package list (base
system, GNOME 50, all apps, hardware/power stack, .NET 11 preview, Intel
VAAPI media drivers) against all repos. Log:
`findings/logs/podman-resolve-full-package-list-1019pkgs-success.log`.

**Result: 1019 packages, zero unresolved dependency conflicts.** Two
new conflicts beyond those in `investigation.md`:

**`dnf5`/`libdnf5`/`dnf5daemon-server`** - `gnome-software-50.3` needs
`dnf5daemon-server(x86-64) >= 5.4.2`, AZL ships `5.2.18.0`. Same
"hand the whole family to one repo" fix as grub2/shim.

**`aznfs`** - Azure Files NFS mount helper (23MB), pulled from `ms-prod`
as a dependency even though nothing we want needs it. Its `%pre`
scriptlet hard-fails without `/proc`. Excluded outright
(`repo --name=ms-prod ... --excludepkgs=aznfs`).

## Container-test cosmetic noise

dnf5's `Transaction failed` after `systemd-udev`'s `%triggerin`
scriptlet fails to write `/etc/udev/hwdb.bin` (`Function not
implemented` in unprivileged containers) is a container-only artifact.
After excluding `aznfs`, the same test completes cleanly.

## Hardware/power gaps (vs. the test host)

AZL4 already ships: `linux-firmware` (full per-vendor split),
`bluez`/`bluez-libs`, `fwupd`/`fwupd-efi`, `microcode_ctl`,
`NetworkManager-wifi`, `wireless-regdb`, and a full kernel family.

Pulled from Fedora 44 (pure userspace daemons, no kernel-ABI coupling):
`upower`, `power-profiles-daemon`, `thermald`, `switcheroo-control`,
`brightnessctl`, `gnome-power-manager`. Intel VAAPI: `libva`,
`libva-intel-media-driver`, `intel-mediasdk`.

## Building an actual ISO: what's available

Image Customizer is Azure Linux's real, current build path - every
config in `toolkit/imageconfigs/` outputs `vhdx`, not ISO. There's no
"Azure Linux installer ISO" built with Image Customizer. But a real
Anaconda-based installer ISO does exist (confirmed by directly mounting
`AzureLinux-4.0-x86_64.iso` - see `reference/azl-installer/` for the
extracted files). It's built with KIWI-NG, not Image Customizer.

Image Customizer's CI needs `losetup -P` (partition-scanning loop
devices), which is confirmed broken on GitHub-hosted runners - that's
why Image Customizer's own upstream CI runs on self-hosted runners.

## The live-ISO build path: lorax + livemedia-creator

Pivoted from trying to feed kickstarts into the AZL installer's
constrained live-boot network stack to using lorax's
`livemedia-creator --no-virt`, which runs `anaconda --dirinstall`
directly on the host with real network. This sidesteps every AZL
installer networking issue.

Key `kickstart/azurelinux-desktop-live.ks` differences from the
installable variant:
- `bootloader --location=none`, flat `part / --size=16384` (nothing
  persists past squashfs capture)
- `shutdown` instead of `reboot`
- NetworkManager only, not systemd-networkd/systemd-resolved
- Adds `livesys-scripts`, `anaconda-live`, `dracut-live`,
  `dracut-config-generic`, `glibc-all-langpacks`
- `liveuser` via `livesys-scripts` (hardcoded, not renameable without
  patching multiple scripts), `%wheel ALL=(ALL) NOPASSWD: ALL`, GDM
  `AutomaticLogin=liveuser`

Confirmed working end-to-end locally: anaconda parsed the mixed
AZL+Fedora+Microsoft+GitHub+RPMFusion kickstart cleanly, resolved
~1100 RPMs (2.47 GiB) without conflict. Log observations from this
build (later fixed in GH Actions):

- `gnome-tour` and `malcontent-control` pulled in as transitive
  dependencies despite not being in `%packages`. Fixed with `-gnome-tour
  -malcontent-control` in `%packages`.
- `livemedia-creator`'s `--resultdir` must NOT already exist.

## Bare metal: the honest options

1. **`dd` the disk image** - exactly what Azure Linux's own release
   process does. No installer, partition sizing baked at build time.
2. **Bundle `anaconda-live`** - Fedora Workstation Live's "Install to
   Hard Drive" copies the live squashfs to disk (no depsolve at install
   time). Least new code.
3. **Custom TUI wrapper** around option 1 - more work, fewer Anaconda
   corner cases.

The installer ISO (see `gh-actions-installer-iso-build.md`) ended up
using KIWI-NG + Anaconda, matching Azure Linux's own actual build path.
