# Canary container - what it is and three bugs found building it

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

## Runtime package canary

`test-container.yml` runs after each published container build. It refreshes
and upgrades the image, then installs optional packages from both sides of the
boundary: Azure `ovfenv` and `telegraf`, Fedora `dconf-editor`, GNOME Sudoku,
and IDLE. The test checks the RPM releases for the expected Azure or Fedora
source, records versions for those packages and every project-specific tool,
and keeps the DNF transaction, enabled-repository, origin, version, and
Flatpak logs as workflow artifacts.

It also installs Firefox, Flatseal, and Polari from Flathub. This is a
repository and installation closure test, not a GUI-launch test. Flatpak can
install and inventory the applications in the non-bootable OCI image, while
Bubblewrap correctly cannot create a sandbox namespace there. The local
`scripts/test-hybrid-container-local.sh` wrapper builds the same canary,
runs the same checks, and keeps its logs outside the repository.

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
