#!/usr/bin/env bash
# shellcheck disable=SC2034
# Nandi OS overrides. scripts/build-iso.sh appends this file to the profiledef.sh
# of archiso's stock "releng" profile, so anything not set here (bootmodes,
# squashfs options, releng's own file permissions) comes from releng.

iso_name="nandios"
iso_label="NANDI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Nandi OS <https://github.com/codegod100/nandios>"
iso_application="Nandi OS Live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
arch="x86_64"
pacman_conf="pacman.conf"
file_permissions+=(
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-nandi-live"]="0:0:440"
  ["/home/nandi"]="1000:1000:750"
  ["/usr/local/bin/nandi-boot-report"]="0:0:755"
)
