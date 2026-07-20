# Desktop repository lifecycle

This project combines an Azure Linux base with a Fedora desktop layer. That
works only as a tested pairing. It is not a rolling-release promise and it is
not safe to switch an installed system to a newer Fedora repository just
because that repository exists.

## The update boundary

Normal updates remain useful while the image's Azure and Fedora repositories
are both supported. The repository exclusions deliberately keep coupled
package families together, so an update does not replace one member with an
incompatible build from the other source.

When the Fedora desktop repository reaches end of life, its archive may keep
old RPMs available, but it no longer provides security fixes. Azure updates
can continue for Azure-owned packages; they do not replace the missing updates
for Fedora-origin desktop packages, libraries, and applications.

Do not automatically redirect an installed image to a newer Fedora release.
This project already depends on carefully tested package-family boundaries.
Changing the desktop repository generation can turn an ordinary update into a
large, untested distribution upgrade.

Sources:

- [Fedora release lifecycle](https://docs.fedoraproject.org/en-US/releases/)
- [Fedora end-of-life policy](https://docs.fedoraproject.org/en-US/releases/eol/)
- [Fedora release-upgrade guidance](https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/)
- [Azure Linux lifecycle](https://learn.microsoft.com/en-us/azure/azure-linux/release-cadence-lifecycle)

## Recommended policy

Treat every published image as one tested Azure Linux and Fedora desktop
generation.

- Routine `dnf upgrade --refresh --best` is reasonable only while that
  generation's repositories and ownership exclusions stay unchanged.
- A Fedora end of life ends supported desktop-layer updates for that image.
- Build and test a new image generation when the Azure base and Fedora desktop
  layer move forward together.
- The normal migration path is backup or VM snapshot, then a clean install of
  the newly published image.
- An in-place repository-generation switch is experimental recovery work on a
  clone, not a documented upgrade path. It must not use broad override flags
  such as `--allowerasing` or disabled exclusions without reviewing the full
  transaction.

Versioned repository snapshots can preserve reproducibility or help recovery,
but they cannot extend upstream security maintenance. Rebuilding the desktop
layer elsewhere would create a downstream maintenance commitment and is not a
near-term replacement for publishing new tested images.

## Proposed README wording

> This is a personal proof of concept, not a supported distribution. Each
> image is a tested point-in-time composition of Azure Linux and a Fedora
> desktop layer.
>
> Normal package updates are appropriate only while the repositories and
> package ownership rules for that image remain unchanged. Use `sudo dnf
> upgrade --refresh --best`, but do not change repository versions or disable
> exclusions manually.
>
> When the desktop repository reaches end of life, Azure Linux updates do not
> replace missing desktop-layer security updates. Back up the system and
> install a newly published image rather than attempting an in-place repository
> switch.
