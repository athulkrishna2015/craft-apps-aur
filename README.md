# Storytold Craft apps — AUR binary packages

This repository maintains prebuilt AUR packages for the Linux releases of six Storytold apps:

| App | AUR package | Upstream |
| --- | --- | --- |
| PDFCraft | [pdfcraft-bin](https://aur.archlinux.org/packages/pdfcraft-bin) | [storytold/pdfcraft](https://github.com/storytold/pdfcraft) |
| DeckCraft | [deckcraft-bin](https://aur.archlinux.org/packages/deckcraft-bin) | [storytold/deckcraft](https://github.com/storytold/deckcraft) |
| GridCraft | [gridcraft-bin](https://aur.archlinux.org/packages/gridcraft-bin) | [storytold/gridcraft](https://github.com/storytold/gridcraft) |
| WordCraft | [wordcraft-bin](https://aur.archlinux.org/packages/wordcraft-bin) | [storytold/wordcraft](https://github.com/storytold/wordcraft) |
| CADCraft | [cadcraft-bin](https://aur.archlinux.org/packages/cadcraft-bin) | [storytold/cadcraft](https://github.com/storytold/cadcraft) |
| SoundCraft | [soundcraft-bin](https://aur.archlinux.org/packages/soundcraft-bin) | [storytold/soundcraft](https://github.com/storytold/soundcraft) |

The packages install upstream prebuilt Linux release tarballs; they do not compile the applications. Each `PKGBUILD` supports both `x86_64` and `aarch64`. `makepkg` selects the matching artifact for the build architecture.

## Automatic updates

The GitHub Actions workflow in `.github/workflows/update-aur.yml` checks upstream GitHub releases hourly at :17 UTC. When a new release is available, `update.sh` updates `pkgver`, refreshes architecture-specific SHA-256 sums from the release's `SHA256SUMS.txt`, regenerates `.SRCINFO`, and pushes the changes to the corresponding AUR package repository. The workflow can also be run manually from the repository's **Actions** tab.

The workflow requires the repository secret `AUR_SSH_PRIVATE_KEY`, whose public key must be registered with the AUR account that maintains these packages. Never commit the private key to this repository.

To run the checker locally without pushing:

```sh
./update.sh
```

To update and push packages from a machine with AUR SSH access:

```sh
./update.sh --push
```

## Package structure

Each package directory contains the AUR `PKGBUILD` and generated `.SRCINFO`:

```text
pdfcraft-bin/
deckcraft-bin/
gridcraft-bin/
wordcraft-bin/
cadcraft-bin/
soundcraft-bin/
```

The package definitions track fixed upstream release versions, as required for reliable AUR updates; they do not resolve a floating `latest` version during package installation.

## Not covered here

[filmcraft-bin](https://aur.archlinux.org/packages/filmcraft-bin) already exists under a different maintainer but is stale (0.2.1 while upstream is at 0.4.0) and flagged out-of-date. Per AUR etiquette this repo does not ship a competing package; if it gets orphaned, it can be adopted and brought up to date instead.
