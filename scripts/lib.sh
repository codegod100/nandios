# shellcheck shell=bash
# Shared helpers for scripts that run inside the builder container.
src=${NANDI_SRC:-/src}
out=$src/out

log() { printf '\e[1;36m==>\e[0m %s\n' "$*"; }
die() { printf '\e[1;31merror:\e[0m %s\n' "$*" >&2; exit 1; }

# Retries a command a few times; mirrors drop connections now and then.
retry() {
    local attempt
    for attempt in 1 2 3 4; do
        "$@" && return 0
        log "Attempt $attempt failed: $*"
        sleep $((attempt * 10))
    done
    return 1
}

# Hand files written by root in the container back to the invoking user.
give_back() {
    [[ -n ${NANDI_UID:-} ]] || return 0
    chown -R "$NANDI_UID:${NANDI_GID:-$NANDI_UID}" "$@"
}

[[ $EUID -eq 0 ]] || die "run this inside the builder container (pixi run ...)"
