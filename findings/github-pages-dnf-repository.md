# Publishing the Azure Linux Desktop DNF repository on GitHub Pages

The USB HID module needs to reach a real Azure Linux install before the next
kernel update does. GitHub Pages is a reasonable place for this project to
publish a small RPM repository. It is public, static, and already tied to the
source repository. There is no web application here. Just RPMs, metadata, and
one URL DNF can consume.

## What is published

The publisher builds two RPMs for every supported Azure kernel:

* `azurelinux-desktop-usbhid-kmod`, the exact external `usbhid` module.
* `azurelinux-desktop-policy`, the package which requires that exact kernel
  and module as one DNF transaction.

It copies the existing RPMs listed in `manifest.txt`, adds the new pair, and
runs `createrepo_c --update`. This preserves older matching pairs. An install
that has not yet moved to the newest Azure kernel can still resolve the module
it needs. Superseded policy RPMs are deliberately excluded during this copy,
so the public repository contains only the current package name.

The public repository root is:

`https://sirredbeard.github.io/azurelinux-desktop/repo/`

The deployed directory has a deliberately boring layout:

```text
repo/
  azurelinux-desktop-policy-<kernel-release>.x86_64.rpm
  azurelinux-desktop-usbhid-kmod-<kernel-release>.x86_64.rpm
  manifest.txt
  repodata/
    repomd.xml
    ...
```

`manifest.txt` is a compact inventory used by the publisher when it preserves
older matching pairs. `repodata/repomd.xml` is the important public check. If
it is readable, DNF has the metadata entry point it expects. The source branch
intentionally does not contain generated RPMs. GitHub Pages serves the
deployed Actions artifact.

The repository is configured as `azl-desktop-kmods` with a low cost in the
live kickstart, installer repository builder, installed-target repo file, and
canary. The normal Azure repository remains the source for the kernel. Pages
only supplies the policy and the exact module built for that kernel.

## Why the policy RPM exists

The module RPM requires one exact `kernel-core-uname-r`. That prevents a
module from being installed against the wrong kernel, but it does not by
itself prevent DNF from selecting a newer kernel without a module.

`azurelinux-desktop-policy` supplies the missing dependency edge. Each policy
RPM requires the exact kernel and exact kmod RPM from its own build. With the
policy installed, a kernel-only update has no complete transaction and stays
out of the update. When the publisher adds the new three-package set, DNF can
select the kernel, policy, and module together.

This is intentionally quiet. It does not replace Azure's kernel repository,
pin all packages, or force an old module into a new kernel. It only declines
an incomplete kernel transition.

## How the workflow builds it

`.github/workflows/publish-usbhid-kmod.yml` runs every four hours and can also
be called before a live ISO, installer ISO, or hybrid-canary build.

1. It queries Azure Linux package metadata for the newest kernel NEVRA.
2. It checks `manifest.txt` for the matching policy RPM. A match ends the run
   before the expensive work starts.
3. If the pair is missing, it starts an Azure Linux container and runs
   `scripts/build-usbhid-kmod.sh`.
4. The script installs the exact `kernel-devel`, verifies the published Azure
   source SHA-512, copies the USB HID source and local headers, then builds
   `usbhid` as an external module against that release's `.config` and
   `Module.symvers`.
5. The workflow regenerates RPM metadata and tests a fresh DNF transaction
   against the staged repository. The test checks the installed module path
   and derives its kernel release from the installed `kernel-core` package.
6. `actions/configure-pages`, `actions/upload-pages-artifact`, and
   `actions/deploy-pages` publish the static `site/` directory.
7. A final curl checks the public `repomd.xml`.

The manual `republish` input is for repository maintenance. It forces a new
build and deployment even when the current policy RPM already exists. That is
how metadata or superseded files can be corrected without waiting for Azure to
publish a new kernel. The reusable workflow declares the same input with a
false default, so image and canary callers keep their normal metadata-only
path.

The publisher's concurrency group serializes repository writes. Image,
installer, and canary callers all run the same fast detector before they
build. The live release wrapper runs that preflight once, then starts separate
ISO and disk-image calls with their internal preflight disabled. This avoids a
race over the shared repository while letting the QCOW2 release immediately
after its own build, without waiting for the ISO.

Pages must exist before the workflow can deploy. The first setup was done
through the GitHub API with `build_type: workflow`; the workflow then uses
`configure-pages` with `enablement: true` so it remains safe if settings need
to be restored. The required workflow permissions are `pages: write` and
`id-token: write`. A workflow that calls an image build through a release
wrapper must grant them too. Reusable workflow permissions can only stay the
same or become narrower, never become broader in the nested call.

## Recovery and verification

For a normal kernel update, let the scheduled publisher detect the missing
policy RPM. For repository maintenance, dispatch the publisher with
`republish: true`. It rebuilds the current pair, reconstructs metadata from
the retained RPMs, drops superseded policy files, deploys Pages, and verifies
the public metadata URL.

The smallest external check is:

```bash
curl --fail --location \
  https://sirredbeard.github.io/azurelinux-desktop/repo/repodata/repomd.xml
```

The meaningful package check is an Azure Linux container with only the Azure
kernel repository and this Pages repository enabled. Install `kernel` and
`azurelinux-desktop-policy`, then verify the `usbhid.ko` path and vermagic.
`scripts/test-hybrid-container.sh` performs the same dependency and module
checks in the published canary.

## How images and installed systems use it

The live kickstart and installer offline-repository builder both add the Pages
repository and install `azurelinux-desktop-policy`. The installer post-install
script leaves the same `.repo` file on the installed target. The hybrid
container uses that repository too, then checks that DNF installed the exact
kernel, policy, and module, including the module's vermagic. See
[`canary-container.md`](canary-container.md) for the canary's broader scope.

This means a user keeps the currently working kernel while Azure publishes a
newer one without its module. Once the publisher has the matching RPM pair,
DNF can move the kernel and `usbhid` together. The container cannot load the
module, but it is still a cheap and useful way to catch a broken repository or
dependency before an image build.
