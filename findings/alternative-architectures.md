# Alternative architectures: sysext, bootc, nspawn, Bluefin, distrobox

Before committing to "mix both distros' RPMs in one dependency graph,
keep a living exclude list," checked whether there's a cleaner way to do
this that other projects have already worked out. None of them make the
ABI problem disappear.

## systemd-sysext / systemd-confext

Sysext overlays `/usr/` and `/opt/` via overlayfs - a namespace trick,
not an ABI boundary. Every binary still runs in the host's process
space, linked against the host's `ld.so`. The glibc version floor
(`mutter-50.3` needing `GLIBC_2.43`, AZL4 shipping 2.42) doesn't go
away just because the binary arrived via squashfs instead of RPM. No
project ships a full desktop this way; real uses are debug tool overlays
and driver packages. **Doesn't help.**

## bootc / OSTree native containers

There's no Azure Linux bootc base image. More importantly:
rpm-ostree's layering still calls the same libdnf dependency resolver.
OSTree changes storage/deployment (atomic, rollback-capable), not
conflict resolution.

The proof: `ublue-os/bluefin-lts` (CentOS Stream 10 + GNOME COPR)
hits the exact same category of conflicts - `libjxl` ABI mismatch,
`glib2` version floor, `fontconfig` symbol requirement,
`selinux-policy` varlink rules - and fixes them with excludes, version
locks, and forced upgrades, functionally identical to this project's
exclude list. **The build model is a real improvement in
reproducibility - worth adopting later - but doesn't avoid the
RPM-level conflicts.**

## systemd-nspawn

Running the whole GNOME session inside an nspawn container with
`--bind=/dev/dri` for direct KMS/DRM access achieves real binary
isolation. But it trades a solvable dependency problem for unsolved
operational ones: competing seat managers, GPU driver drift risk,
manual socket bridging for PipeWire and D-Bus. Nobody runs a real
direct-KMS GNOME session this way. **More complex for no net benefit.**

## Universal Blue / Bluefin

Bluefin proper is single-ecosystem Fedora Silverblue, so it has no
cross-distro conflicts - that's *why* it works, and that condition
doesn't exist here. Bluefin-LTS (above) is the relevant analogy, and
it's independent confirmation that this class of conflict is normal
and known. **Validates the approach, doesn't offer a shortcut.**

## Toolbox / distrobox app export

Sidesteps the ABI problem completely for individual apps (each runs in
its own container's userspace). Catch: "only individual applications,
not full user desktop sessions" - gnome-shell/mutter can't be exported
as an app. **Doesn't replace the GNOME session, but is the right tool
for anything added later that would extend the exclude list** - same
pattern Bluefin uses (Flatpak for sandboxed GUI apps, distrobox for
anything that would conflict at the OS package level).

## Prior art

`Nue-Houjuu/azurelinux-fedora-repo-installer` independently does the
same thing (Fedora repos on Azure Linux for XFCE/KDE) - unaffiliated
confirmation this is a known, if under-documented, path.
