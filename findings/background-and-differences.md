# Background: how this project got here, and what's different from the WSL version

## Starting point: what's on the Azure Linux 4.0 ISO

Pulled apart `AzureLinux-4.0-x86_64.iso` without root access (`7z` for
the ISO structure, `debugfs` for the embedded ext4 `rootfs.img`):

- Real Anaconda installer with standard kickstart syntax (`%packages
  --nocore`, `%post --nochroot`).
- Custom boot flow: `azl.autoinstall` (not `inst.ks=`) triggers a
  dracut hook that hands off to `/usr/local/bin/anaconda-launcher.sh`.
- `/etc/os-release`: `ID=azurelinux`, `ID_LIKE=fedora` - the
  `ID_LIKE` is load-bearing.

A kickstart-based unattended install was the right target format from
the start.

## First attempt used the wrong Fedora release

First pass paired AZL4 against Fedora rawhide (the easiest to reach
for locally). Azure Linux 4.0's `glibc` is `2.42-10.azl4`, Fedora 43's
is `2.42-4.fc43` - same upstream snapshot. Rawhide is already at
`glibc-2.43.9000`, two releases of drift ahead. Switching to Fedora 44
(one release ahead, stable GNOME 50) took this from "constant
conflicts" to "three specific, fixable conflicts." The right question
is always "what release is the target distro closest to," not "what's
newest."

## Bootloader-specific things worth remembering

- AZL4's `grub2-tools-minimal` links against `libfuse3.so.3`, Fedora's
  `flatpak`/`xdg-desktop-portal` need `libfuse3.so.4` - mutually
  exclusive. Fix: hand the whole grub2/shim family to Fedora. See
  `investigation.md`.
- Container-test `grub2-probe`/`grub2-editenv`/`udev` warnings and
  `Transaction failed` messages are container-only false negatives.
  Confirm success with `rpm -qa`, not dnf5's exit message.

## What's different from the WSL version

| Aspect | WSL version | This project |
|---|---|---|
| Display path | WSLg (Wayland/X11→RDP→WinUI) | Direct GDM→mutter→DRM/KMS |
| Package provenance | Single curated container, no cross-distro mixing | Full mixed AZL+Fedora dependency graph |
| Host OS | Windows supplies WSL, GPU drivers, session management | No host - AZL4 does everything |
| Boot chain | WSL VM kernel from Windows, no bootloader | Real grub2/shim/kernel - the sharpest ABI conflict |
| Goal | Cosmetic/integration (themed XFCE in WinUI) | Correctness (does GNOME actually boot and run) |

## Prior art

- `Nue-Houjuu/azurelinux-fedora-repo-installer` - adds Fedora repos to
  Azure Linux for XFCE/KDE. Unaffiliated, confirms the basic approach.
- `ublue-os/bluefin-lts` - CentOS Stream 10 + GNOME 50 COPR, identical
  conflict category, same fix tools. See `alternative-architectures.md`.
