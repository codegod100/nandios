#!/usr/bin/env bash
# Runs build steps inside the Arch Linux builder container.
#   container.sh build-image      build the builder image
#   container.sh run CMD [ARGS]   run CMD in it with the repo mounted at /src
# NANDI_ENGINE picks docker or podman (default: podman if installed, else docker).
# Rootless podman is run with sudo, since mkarchiso needs a rootful container.
# The container is privileged because mkarchiso needs mounts for pacstrap.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
engine=${NANDI_ENGINE:-$(command -v podman || command -v docker || true)}
image=${NANDI_IMAGE:-localhost/nandios-builder:latest}
[[ -n $engine ]] || { echo 'Need podman or docker.' >&2; exit 1; }

# pacstrap mounts devtmpfs and friends, which a rootless container may not do,
# so rootless podman runs through sudo (set NANDI_ROOTLESS=1 to skip that).
engine=("$engine")
if [[ ${engine[0]##*/} == podman && $EUID -ne 0 && -z ${NANDI_ROOTLESS:-} ]]; then
    echo 'Using sudo for podman: building the ISO needs a rootful container.' >&2
    engine=(sudo "${engine[0]}")
fi

case ${1:-} in
    build-image)
        "${engine[@]}" build --pull -t "$image" -f "$root/container/Containerfile" "$root/container"
        ;;
    run)
        shift
        args=(--rm --privileged -v "$root:/src" -w /src
              -e "NANDI_UID=$(id -u)" -e "NANDI_GID=$(id -g)")
        for var in SOURCE_DATE_EPOCH NANDI_KDE_REF NANDI_TEST_TIMEOUT NANDI_TEST_CASES NANDI_TEST_JOBS NANDI_TEST_MEM NANDI_SQUASHFS; do
            [[ -z ${!var:-} ]] || args+=(-e "$var=${!var}")
        done
        mirrorlist=${NANDI_MIRRORLIST:-}
        [[ -n $mirrorlist || ! -f /etc/arch-release ]] || mirrorlist=/etc/pacman.d/mirrorlist
        [[ -z $mirrorlist ]] || args+=(-v "$(realpath "$mirrorlist"):/etc/pacman.d/mirrorlist:ro")
        # Keep downloaded packages between runs (NANDI_PKG_CACHE, default .cache/pkg).
        pkg_cache=${NANDI_PKG_CACHE:-$root/.cache/pkg}
        mkdir -p "$pkg_cache"
        args+=(-v "$(realpath "$pkg_cache"):/var/cache/pacman/pkg")
        # NANDI_WORK_DIR puts mkarchiso's scratch space (~15 GB) on a host
        # directory instead of the container's own storage.
        if [[ -n ${NANDI_WORK_DIR:-} ]]; then
            mkdir -p "$NANDI_WORK_DIR"
            args+=(-v "$(realpath "$NANDI_WORK_DIR"):/var/tmp/nandi-work")
        fi
        [[ ! -e /dev/kvm ]] || args+=(--device /dev/kvm)
        [[ ! -t 0 || ! -t 1 ]] || args+=(-it)
        exec "${engine[@]}" run "${args[@]}" "$image" "$@"
        ;;
    *)
        echo "Usage: $0 build-image | run CMD [ARGS...]" >&2
        exit 2
        ;;
esac
