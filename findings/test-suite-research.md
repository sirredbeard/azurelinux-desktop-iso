# Testing this thing for real, not just building it

Everything up to this point was about getting ISOs/images to build. This
is the research behind building a real test suite instead of eyeballing
QEMU by hand.

## What's worth borrowing

**Fedora's openQA suite** (`fedora-qa/os-autoinst-distri-fedora`, Pagure) -
too heavy to deploy wholesale, but the test *intent* is the model:
- `_boot_to_anaconda.pm` / `_graphical_wait_login.pm` - boot, GDM, login.
- `_advisory_update.pm` + `script_retry()` - update-health testing with
  dnf5 locking race retries.
- `advisory_check_nonmatching_packages()` - expected-vs-actual package
  versions after update (exactly what this project needs for the
  AZL/Fedora repo priority check post-upgrade).

**AlmaLinux's `compose-tests`** - best public example of `tmt`/`fmf` from
GitHub Actions. Boots via Vagrant, runs `tmt ... provision --how=local`
inside. That's the shape to copy: boot the image, run tests inside via
SSH/serial. `tmt`'s virtual provisioner (wants libvirt/testcloud + KVM)
has no working public example on hosted runners, and its code multiplies
boot timeouts by 10x without `/dev/kvm`.

**Rocky's openQA fork** (`os-autoinst-distri-rocky`) has a working
Flatpak/Flathub test: adds remote, installs `org.gnome.clocks`, confirms
install. Directly reusable pattern.

**KIWI has no built-in appliance self-test.** Nothing to borrow.

**DNF/repo-priority regression testing has no ready-made framework**
anywhere (DNF5's own test suite has a literal TODO for priority testing).

## The realistic test shape

1. **Boot smoke test** - plain `qemu-system-x86_64` (TCG), serial
   console, wait for login/GDM marker.
2. **Post-boot in-guest checks** (SSH or serial): `dnf upgrade`, repo
   priority assertions, AZL+Fedora+Flathub install tests.
3. **Container-only fast checks** - package-resolution/repo-priority
   checks that don't need a booted system.
4. **Container image test** - pull and test the published hybrid
   container independently of ISO/disk-image checks.
