#!/usr/bin/env bash
# Builds every PKGBUILD under packages/ and publishes them as the local
# [nandi] pacman repo in out/repo.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

repo=$out/repo
build=/var/tmp/nandi-pkgbuild
rm -rf "$build"
mkdir -p "$build/pkgs"

pacman -Sy --noconfirm

for dir in "$src"/packages/*/; do
    name=$(basename "$dir")
    log "Building $name"
    cp -a "$dir" "$build/$name"
    chown -R builder: "$build"
    # Packages without makedepends are data-only and may depend on our own
    # packages, which no repo has yet, so skip the dependency check for them.
    deps=--syncdeps
    grep -q '^makedepends=' "$dir/PKGBUILD" || deps=--nodeps
    (cd "$build/$name" && runuser -u builder -- env PKGDEST="$build/pkgs" NANDI_KDE_REF="${NANDI_KDE_REF:-}" \
        makepkg --noconfirm --cleanbuild "$deps")
done

log "Publishing repo in $repo"
rm -rf "$repo"
mkdir -p "$repo"
find "$build/pkgs" -name '*.pkg.tar.*' ! -name '*-debug-*' -exec cp -t "$repo" {} +
repo-add "$repo/nandi.db.tar.zst" "$repo"/*.pkg.tar.*
give_back "$out"
ls -lh "$repo"
