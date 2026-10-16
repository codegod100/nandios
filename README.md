# Nandi OS

An Arch Linux based live distro with KDE Plasma 6, booted by
[Limine](https://github.com/limine-bootloader/limine) on both BIOS and UEFI.
It ships the KDE projects from [codegod100/kde](https://github.com/codegod100/kde):

- **Loop Eyes**: the panel head whose eyes follow the cursor (its KWin script is enabled by default)
- **Whitelist System Tray**: replaces the stock tray in the default panel
- **Flatkit** window decorations: the default KWin decoration

The live session logs in to Plasma automatically as `nandi` (no password,
passwordless sudo). To install to disk, run **Install Nandi OS** on the desktop
(`sudo archinstall --config /etc/nandi/archinstall.json`). The config preselects
the KDE Plasma profile with Plasma Login Manager, NetworkManager and PipeWire; you still pick the
disk, user and bootloader (choose Limine). The installed system is plain Arch
with Plasma; the Nandi packages are only on the live ISO for now.

## Build

You need [pixi](https://pixi.sh) and podman or docker. Everything else runs in
an Arch Linux container, so the host can be any Linux distro.

```sh
pixi run build-iso   # builds packages/ and then out/nandios-<date>-x86_64.iso
pixi run test-iso    # headless QEMU boot test: BIOS/UEFI x CD/USB, results in out/test/
pixi run run-iso     # try it in a QEMU window (pixi run run-iso bios for BIOS)
```

Write it to a USB stick with `sudo dd if=out/nandios-*.iso of=/dev/sdX bs=4M oflag=sync status=progress`,
or copy it onto a [Ventoy](https://www.ventoy.net) stick. Under Ventoy the ISO is only a
file on the stick, so the `nandi_iso_search` initramfs hook finds that file by
the ISO's UUID and loop-mounts it.

Downloaded packages are kept in `.cache/pkg` (or `NANDI_PKG_CACHE`), so rebuilds
only fetch what changed. The root image is zstd-compressed for speed; set
`NANDI_SQUASHFS=xz` for a smaller ISO.

Other tasks: `pixi run rebuild-iso` (reuse built packages), `pixi run shell`
(shell in the builder), `pixi run lint`, `pixi run clean`. Set
`NANDI_ENGINE=docker` to force docker when podman is also installed, and
`NANDI_KDE_REF=<commit>` to pin the codegod100/kde commit that gets packaged.
Rootless podman is run through `sudo` because mkarchiso needs a rootful
container. Downloads fall back across several mirrors (`container/mirrorlist`);
on an Arch host your own mirrorlist is used, or set `NANDI_MIRRORLIST=/path`.

GitHub Actions builds and boot-tests the ISO on every push to `main` and
uploads it as the `nandios-iso` artifact, with serial logs and screenshots of
each boot in `boot-test`.

## How it is put together

| Path | What |
| --- | --- |
| `container/Containerfile` | Arch builder image: archiso, limine, makepkg, QEMU + OVMF |
| `packages/nandi-kde` | Split PKGBUILD for Loop Eyes, the whitelist tray and Flatkit, built from codegod100/kde |
| `packages/nandi-desktop` | Plasma defaults: the `org.nandi.desktop` look-and-feel with the panel layout, `/etc/xdg` kwinrc/kdeglobals |
| `profile/` | Changes on top of archiso's `releng` profile: extra packages, live user, SDDM autologin, NetworkManager |
| `profile/limine/limine.conf` | Boot menu (normal, safe graphics, copy to RAM) |
| `scripts/build-iso.sh` | Runs mkarchiso for the root filesystem, then re-masters the ISO with Limine via xorriso + `limine bios-install` |

archiso has no Limine boot mode, so mkarchiso builds the squashfs, kernel and
initramfs with the stock releng boot modes, and `build-iso.sh` throws its boot
files away and builds a hybrid ISO where Limine is the only bootloader. The
kernel finds the root image with `archisolabel=`, which matches the ISO volume label.
