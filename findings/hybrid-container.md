# Hybrid container publishing - what it is and three bugs found building it

`scripts/build-hybrid-container.sh` + `.github/workflows/build-container.yml`
publish a small OCI image to GHCR (`ghcr.io/sirredbeard/azurelinux-desktop/hybrid`)
straight from the kickstart's own repo/priority setup. A fast proof that
the Azure-Linux-base + Fedora-GNOME-layer repo priority split still
resolves packages from the intended repo, pullable without running a
build.

## What it deliberately is not

Not a containerized desktop. It installs the project-specific package and
side-load boundary: Azure identity/repository packages, the Fedora GTK and
Plymouth families, Edge Canary, PowerShell, VS Code Insiders, GitHub CLI and
Desktop, .NET, Flatpak, Copilot GUI/CLI, and `microsoft/edit`. This gives the
canary a useful dependency closure for every custom repository and executable
without installing a GNOME session, GDM, Mutter, or a desktop package group.
Some GUI libraries are expected as dependencies; a working GUI is not.

The container derives the repository definitions and costs from the live
kickstart, so it carries the same Azure-preferred/Fedora-fallback policy as
the live image. It downloads the two side-loaded archives and Copilot GUI RPM
from the same upstream endpoints as the installer, verifies the Copilot CLI
checksum, installs the RPM through the derived repositories, and asserts that
the resulting `copilot` and `edit` executables exist.

## Precedent

Mirrors Azure Linux's own `container-base` approach
(`microsoft/azurelinux`'s `base/images/container-base/container-base.kiwi`):
tiny, non-bootable, no systemd, `machine-bootable=false`. This project
uses `dnf --installroot` + `podman import` instead of KIWI.

## Three bugs found dogfood-testing

1. **`chroot /mnt/azl rpm -qa` failed (exit 127)** - no `rpm` binary
   in the installed set (only `librpm` came in transitively). Fix: query
   from the host with `rpm --root=/mnt/azl -qa`.

2. **Installed rootfs vanished after container exit.** `dnf5
   --installroot=/mnt/azl` ran inside ephemeral `podman run --rm`, and
   `/mnt/azl` was never bind-mounted to a host path. Fix:
   `-v "$ROOTFS:/mnt/azl:Z"`.

3. **`tar` failed with "Permission denied" on `/etc/shadow`.** These
   files are root-owned within rootless-podman's user-namespace
   mapping. Fix: `podman unshare tar ...` / `podman unshare rm -rf ...`.

## Confirmed working

Local: 547MB image, correct repo sourcing, `/etc/os-release` reports
Azure Linux 4.0. CI run
[29652166344](https://github.com/sirredbeard/azurelinux-desktop/actions/runs/29652166344):
pushed `:latest` and UTC-date tag to GHCR, pulled back and verified.
