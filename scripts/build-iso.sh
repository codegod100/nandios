#!/usr/bin/env bash
# Builds the Nandi OS live ISO.
#  1. Stage a profile: archiso's stock releng profile with profile/ on top.
#  2. Let mkarchiso build the root filesystem image, kernel and initramfs.
#  3. Re-master the ISO with Limine as the only bootloader, for BIOS and UEFI,
#     as a hybrid image that boots from optical media and USB sticks.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

releng=/usr/share/archiso/configs/releng
repo=$out/repo
work=${NANDI_WORK:-/var/tmp/nandi-work}
profile=$work/profile
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date +%s)}

[[ -f $repo/nandi.db ]] || die "no package repo in $repo; run 'pixi run build-packages' first"

log "Staging profile"
rm -rf "$work"
mkdir -p "$work" "$out"
cp -a "$releng" "$profile"
cp -a "$src/profile/airootfs/." "$profile/airootfs/"

# NetworkManager replaces releng's iwd + systemd-networkd setup.
rm -rf "$profile/airootfs/etc/systemd/network"
find "$profile/airootfs/etc/systemd/system" -lname '*iwd.service' -delete
find "$profile/airootfs/etc/systemd/system" -lname '*systemd-networkd*' -delete

cat "$src/profile/profiledef.sh" >> "$profile/profiledef.sh"
cat "$releng/packages.x86_64" "$src/profile/packages.x86_64" \
    | sed -e 's/#.*//' -e 's/[[:space:]]//g' | awk 'NF && !seen[$0]++' > "$profile/packages.x86_64"
sed "s|@NANDI_REPO@|$repo|" "$src/profile/pacman.conf" > "$profile/pacman.conf"

profile_var() {
    bash -c 'declare -A file_permissions=(); source "$1"; printf %s "${!2}"' _ "$profile/profiledef.sh" "$1"
}
label=$(profile_var iso_label)
version=$(profile_var iso_version)
name=$(profile_var iso_name)

log "Running mkarchiso"
# A retry resumes where mkarchiso stopped (it skips steps already done).
retry mkarchiso -v -w "$work/build" -o "$work/mkarchiso-out" "$profile"
rm -rf "$work/mkarchiso-out"   # mkarchiso's own ISO; we only want its pieces

log "Assembling Limine ISO"
isoroot=$work/limine-iso
mkdir -p "$isoroot/boot/limine" "$isoroot/EFI/BOOT"
mv "$work/build/iso/arch" "$isoroot/arch"
[[ -f $isoroot/arch/boot/x86_64/vmlinuz-linux ]] || die "kernel missing from mkarchiso output"

modules=""
for ucode in "$isoroot"/arch/boot/{intel,amd}-ucode.img; do
    [[ -f $ucode ]] && modules+="    module_path: boot():/arch/boot/${ucode##*/}"$'\n'
done
modules+="    module_path: boot():/arch/boot/x86_64/initramfs-linux.img"
conf=$(<"$src/profile/limine/limine.conf")
conf=${conf//@LABEL@/$label}
conf=${conf//@MODULES@/$modules}
printf '%s\n' "$conf" > "$isoroot/boot/limine/limine.conf"

cp /usr/share/limine/limine-bios.sys /usr/share/limine/limine-bios-cd.bin \
   /usr/share/limine/limine-uefi-cd.bin "$isoroot/boot/limine/"
cp /usr/share/limine/BOOTX64.EFI /usr/share/limine/BOOTIA32.EFI "$isoroot/EFI/BOOT/"

iso=$out/$name-$version-x86_64.iso
rm -f "$iso" "$iso.sha256"
xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid "$label" -appid "Nandi OS Live" -publisher "Nandi OS" \
    -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
    --protective-msdos-label \
    -o "$iso" "$isoroot"
limine bios-install "$iso"

(cd "$out" && sha256sum "${iso##*/}" > "${iso##*/}.sha256")
rm -rf "$work"
give_back "$out"
log "Built $iso ($(du -h "$iso" | cut -f1))"
