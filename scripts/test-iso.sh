#!/usr/bin/env bash
# Boots the ISO headless in QEMU from BIOS and UEFI, as a CD and as a USB
# stick, and waits for the live session to reach a running Plasma desktop.
# Writes serial logs and screenshots to out/test/.
#   test-iso.sh [ISO]   (default: newest out/*.iso)
# NANDI_TEST_CASES limits the cases, e.g. "uefi-cd bios-usb".
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

iso=${1:-$(ls -t "$out"/*.iso 2>/dev/null | head -n1)}
[[ -f $iso ]] || die "no ISO found; run 'pixi run build-iso' first"
results=$out/test
rm -rf "$results"
mkdir -p "$results"

if [[ -w /dev/kvm ]]; then
    accel=(-accel kvm -cpu host)
    timeout=${NANDI_TEST_TIMEOUT:-420}
else
    log "No /dev/kvm: using slow software emulation"
    accel=(-accel tcg -cpu max)
    timeout=${NANDI_TEST_TIMEOUT:-2400}
fi
ovmf_code=/usr/share/edk2/x64/OVMF_CODE.4m.fd
ovmf_vars=/usr/share/edk2/x64/OVMF_VARS.4m.fd

read -ra cases <<<"${NANDI_TEST_CASES:-bios-cd uefi-cd bios-usb uefi-usb}"
port=4440
failed=0

for case in "${cases[@]}"; do
    port=$((port + 1))
    serial=$results/$case.serial.log
    fw=() media=()
    case $case in
        uefi-*)
            cp "$ovmf_vars" "$results/$case.vars.fd"
            fw=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
                -drive "if=pflash,format=raw,file=$results/$case.vars.fd") ;;
    esac
    case $case in
        *-cd) media=(-cdrom "$iso") ;;
        *-usb) media=(-device qemu-xhci -drive "if=none,id=stick,format=raw,readonly=on,file=$iso"
                      -device usb-storage,drive=stick,bootindex=0) ;;
        *) die "unknown test case $case" ;;
    esac

    log "Booting $case (timeout ${timeout}s)"
    qemu-system-x86_64 "${accel[@]}" -machine q35 -m 4096 -smp 4 \
        -vga virtio -display none \
        -serial "file:$serial" -monitor "tcp:127.0.0.1:$port,server,nowait" \
        -nic user,model=virtio-net-pci "${fw[@]}" "${media[@]}" &
    qemu=$!

    result=TIMEOUT
    for ((t = 0; t < timeout; t += 5)); do
        sleep 5
        if grep -qa NANDI_PLASMA_OK "$serial"; then result=PASS; break; fi
        if grep -qa NANDI_PLASMA_TIMEOUT "$serial"; then result=FAIL; break; fi
        kill -0 "$qemu" 2>/dev/null || { result=QEMU_EXITED; break; }
    done

    if kill -0 "$qemu" 2>/dev/null; then
        [[ $result == PASS ]] && sleep 20   # let the desktop finish painting
        {
            exec 3<>"/dev/tcp/127.0.0.1/$port"
            printf 'screendump %s -f png\n' "$results/$case.png" >&3
            sleep 3
            printf 'quit\n' >&3
            sleep 1
        } 2>/dev/null || true
        sleep 2
        kill "$qemu" 2>/dev/null || true
    fi
    wait "$qemu" 2>/dev/null || true
    rm -f "$results/$case.vars.fd"

    units=$(grep -a NANDI_FAILED_UNITS "$serial" | tail -n1 | tr -d '\r' || true)
    printf '%-10s %-12s %s\n' "$case" "$result" "${units#NANDI_FAILED_UNITS }" | tee -a "$results/summary.txt"
    [[ $result == PASS ]] || failed=1
done

give_back "$results"
exit "$failed"
