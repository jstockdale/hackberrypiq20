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
  [[ "${EUID}" -eq 0 ]] || die "Please run as root (sudo ./uninstall.sh)"
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

remove_overlay() {
  section "Remove device-tree overlay"

  must_exec sed -i "\|^dtoverlay=${DT_NAME}$|d" "${CONFIG_TXT}"
  rm -f "${OVERLAY_DIR}/${DT_NAME}.dtbo" || true

  log "Overlay removed"
}

remove_dkms() {
  section "Remove DKMS module"

  if dkms status -m "${PKG_NAME}" -v "${PKG_VER}" >/dev/null 2>&1; then
    must_exec dkms remove -m "${PKG_NAME}" -v "${PKG_VER}" --all
  else
    log "No DKMS entry found"
  fi
}

remove_sources() {
  section "Remove DKMS sources"

  rm -rf "${DKMS_SRC_DIR}" || true
}

print_status() {
  section "Status"

  log "DKMS status:"
  dkms status | while IFS= read -r line; do
    log "  ${line}"
  done || true

  log "Overlay present: $(test -f "${OVERLAY_DIR}/${DT_NAME}.dtbo" && echo yes || echo no)"
}

main() {
  need_root
  remove_overlay
  remove_dkms
  remove_sources
  print_status

  echo
  log "[✓] Uninstall complete. Reboot recommended: sudo reboot"
}

main "$@"

