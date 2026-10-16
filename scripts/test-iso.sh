#!/usr/bin/env bash
# Boots the ISO headless in QEMU from BIOS and UEFI, as a CD and as a USB
# stick, and waits for the live session to reach a running Plasma desktop.
# Writes serial logs and screenshots to out/test/.
#   test-iso.sh [ISO]   (default: newest out/*.iso)
# The iso-file case mimics Ventoy: the ISO is a file on a USB stick's
# filesystem and the kernel is started directly, so the initramfs has to find
# and loop-mount the file itself.
# NANDI_TEST_CASES limits the cases, e.g. "uefi-cd bios-usb"; NANDI_TEST_JOBS
# sets how many boot at once (default 3), NANDI_TEST_MEM the RAM per VM in MiB.
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

read -ra cases <<<"${NANDI_TEST_CASES:-bios-cd uefi-cd bios-usb uefi-usb iso-file}"

# Ventoy-like stick: an ext4 filesystem holding the ISO as a file, plus the
# kernel, initramfs and command line taken from the ISO.
make_iso_file_stick() {
    local stage=$results/iso-file
    mkdir -p "$stage/stick/isos"
    xorriso -osirrox on -indev "$iso" -extract /arch/boot/x86_64 "$stage/boot" \
        -extract /boot/limine/limine.conf "$stage/limine.conf" >/dev/null 2>&1
    chmod -R u+rw "$stage/boot"
    ln "$iso" "$stage/stick/isos/" 2>/dev/null || cp "$iso" "$stage/stick/isos/"
    truncate -s "$(( $(stat -c %s "$iso") / 1048576 + 512 ))M" "$stage/stick.img"
    mkfs.ext4 -q -L STICK -d "$stage/stick" "$stage/stick.img"
    rm -rf "$stage/stick"
    iso_file_cmdline=$(grep -m1 'cmdline:' "$stage/limine.conf" | sed 's/^ *cmdline: *//')
}
# Boots one case and records PASS/FAIL in $results/<case>.result.
run_case() {
    local case=$1 port=$2
    local serial=$results/$case.serial.log result qemu t units
    local fw=() media=()
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
        iso-file)
            make_iso_file_stick
            media=(-kernel "$results/iso-file/boot/vmlinuz-linux"
                   -initrd "$results/iso-file/boot/initramfs-linux.img"
                   -append "$iso_file_cmdline"
                   -device qemu-xhci -drive "if=none,id=stick,format=raw,readonly=on,file=$results/iso-file/stick.img"
                   -device usb-storage,drive=stick) ;;
        *) echo "unknown test case $case" >&2; echo FAIL > "$results/$case.result"; return ;;
    esac

    log "Booting $case (timeout ${timeout}s)"
    qemu-system-x86_64 "${accel[@]}" -machine q35 -m "$mem" -smp 2 \
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
    rm -rf "$results/$case.vars.fd"
    [[ $case != iso-file ]] || rm -rf "$results/iso-file"

    units=$(grep -a NANDI_FAILED_UNITS "$serial" | tail -n1 | tr -d '\r' || true)
    printf '%-10s %-12s %s\n' "$case" "$result" "${units#NANDI_FAILED_UNITS }"
    echo "$result" > "$results/$case.result"
}

# Boot several cases at once; each VM gets 2 CPUs.
max_jobs=${NANDI_TEST_JOBS:-3}
mem=${NANDI_TEST_MEM:-3072}
port=4440
for case in "${cases[@]}"; do
    while (( $(jobs -rp | wc -l) >= max_jobs )); do wait -n || true; done
    port=$((port + 1))
    run_case "$case" "$port" &
done
wait

failed=0
for case in "${cases[@]}"; do
    result=$(cat "$results/$case.result" 2>/dev/null || echo MISSING)
    printf '%-10s %s\n' "$case" "$result" >> "$results/summary.txt"
    [[ $result == PASS ]] || failed=1
    rm -f "$results/$case.result"
done
log "Summary"
cat "$results/summary.txt"

give_back "$results"
exit "$failed"
