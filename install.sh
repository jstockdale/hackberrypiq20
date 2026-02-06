#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PKG_NAME="hackberrypi-max17048"
PKG_VER="$(cat "${SCRIPT_DIR}/VERSION")"
DT_NAME="hackberrypicm5"

CONFIG_TXT="/boot/firmware/config.txt"
OVERLAY_DIR="/boot/firmware/overlays"
DKMS_SRC_DIR="/usr/src/${PKG_NAME}-${PKG_VER}"

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log()  { echo "[$(ts)] $*"; }
warn() { echo "[$(ts)] WARNING: $*" >&2; }
err()  { echo "[$(ts)] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Please run as root (sudo ./install.sh)"
}

exec_cmd() {
  local cmd=("$@")

  printf '[%s] [*] ' "$(ts)"
  printf '%q ' "${cmd[@]}"
  printf '\n'

  "${cmd[@]}"
  local status=$?

  if [[ $status -eq 0 ]]; then
    log "[✓] Success"
  else
    err "[✗] Failed (exit code ${status})"
  fi

  return $status
}

must_exec() {
  if ! exec_cmd "$@"; then
    err "Aborting due to previous error"
    exit 1
  fi
}

section() {
  echo
  log "=== $* ==="
}

check_prereqs() {
  [[ -f "${SCRIPT_DIR}/dkms.conf" ]] || die "Missing dkms.conf"
  [[ -f "${SCRIPT_DIR}/Makefile"  ]] || die "Missing Makefile"
  [[ -f "${SCRIPT_DIR}/${DT_NAME}.dts" ]] || die "Missing ${DT_NAME}.dts"
  [[ -f "${CONFIG_TXT}" ]] || die "Missing ${CONFIG_TXT}"
  [[ -d "${OVERLAY_DIR}" ]] || die "Missing ${OVERLAY_DIR}"

  for cmd in dkms make dtc rsync; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Missing dependency: ${cmd}"
  done

  [[ -d "/lib/modules/$(uname -r)/build" ]] || \
    die "Kernel headers missing: sudo apt install linux-headers-$(uname -r)"
}

sync_sources() {
  section "Sync DKMS source tree"
  must_exec mkdir -p "${DKMS_SRC_DIR}"

  must_exec rsync -a --delete \
    --exclude '.git' \
    --exclude '*.dtbo' \
    --exclude 'install.sh' \
    --exclude 'uninstall.sh' \
    "${SCRIPT_DIR}/" "${DKMS_SRC_DIR}/"
}

dkms_install() {
  section "DKMS add / build / install"

  if dkms status -m "${PKG_NAME}" -v "${PKG_VER}" >/dev/null 2>&1; then
    log "DKMS entry already exists"
  else
    must_exec dkms add -m "${PKG_NAME}" -v "${PKG_VER}"
  fi

  must_exec dkms build   -m "${PKG_NAME}" -v "${PKG_VER}"
  must_exec dkms install -m "${PKG_NAME}" -v "${PKG_VER}"
}

install_overlay() {
  section "Install device-tree overlay"

  must_exec dtc -I dts -O dtb \
    -o "${SCRIPT_DIR}/${DT_NAME}.dtbo" \
       "${SCRIPT_DIR}/${DT_NAME}.dts"

  must_exec install -m 0644 \
    "${SCRIPT_DIR}/${DT_NAME}.dtbo" \
    "${OVERLAY_DIR}/${DT_NAME}.dtbo"

  must_exec sed -i "\|^dtoverlay=${DT_NAME}$|d" "${CONFIG_TXT}"
  echo "dtoverlay=${DT_NAME}" >> "${CONFIG_TXT}"

  log "Overlay installed and enabled"
}

print_status() {
  section "Status"

  log "DKMS status:"
  dkms status | while IFS= read -r line; do
    log "  ${line}"
  done

  log "Overlay present: $(test -f "${OVERLAY_DIR}/${DT_NAME}.dtbo" && echo yes || echo no)"
  log "Overlay enabled: $(grep -q "^dtoverlay=${DT_NAME}$" "${CONFIG_TXT}" && echo yes || echo no)"
}

main() {
  need_root
  check_prereqs
  sync_sources
  dkms_install
  install_overlay
  print_status

  echo
  log "[✓] Install complete. Reboot required: sudo reboot"
}

main "$@"

