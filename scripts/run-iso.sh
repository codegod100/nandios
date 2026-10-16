#!/usr/bin/env bash
# Boots the ISO in a QEMU window on the host to try it out.
#   run-iso.sh [uefi|bios] [ISO]
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-uefi}
iso=${2:-$(ls -t "$root"/out/*.iso 2>/dev/null | head -n1)}
[[ -f $iso ]] || { echo "No ISO found; run 'pixi run build-iso' first." >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo 'Install QEMU (qemu-system-x86_64) on the host.' >&2; exit 1; }

args=(-machine q35 -m 4096 -smp 4 -vga virtio -nic user,model=virtio-net-pci -cdrom "$iso")
[[ -w /dev/kvm ]] && args+=(-accel kvm -cpu host)

if [[ $mode == uefi ]]; then
    for code in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd \
                /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f $code ]] && break
    done
    [[ -f $code ]] || { echo 'OVMF not found; install edk2-ovmf (or ovmf), or use: run-iso bios' >&2; exit 1; }
    vars=$(mktemp)
    trap 'rm -f "$vars"' EXIT
    cp "${code/CODE/VARS}" "$vars"
    args+=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
fi

qemu-system-x86_64 "${args[@]}"
