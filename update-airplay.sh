#!/usr/bin/env bash
# Update and rebuild NQPTP and Shairport Sync from git on Raspberry Pi OS (systemd).
# Uses the default build options from the Shairport Sync BUILD guide.
# Usage: ./update-airplay.sh [--force]   (--force rebuilds even if already up to date)
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/src}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

log() { printf '\n==> %s\n' "$*"; }

# Clone or fast-forward a repo. Returns 0 if it changed (or --force), 1 if already current.
update_repo() {
  local url="$1" dir="$2"
  if [[ ! -d "$dir/.git" ]]; then
    log "Cloning $url"
    git clone "$url" "$dir"
  fi
  git -C "$dir" fetch --quiet --tags origin
  local local_rev remote_rev
  local_rev="$(git -C "$dir" rev-parse HEAD)"
  remote_rev="$(git -C "$dir" rev-parse '@{u}')"
  if [[ "$local_rev" == "$remote_rev" && $FORCE -eq 0 ]]; then
    log "$(basename "$dir") is already up to date ($(git -C "$dir" describe --always --dirty))"
    return 1
  fi
  log "Updating $(basename "$dir")"
  git -C "$dir" pull --ff-only
  return 0
}

install_deps() {
  log "Installing build dependencies"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends build-essential git autoconf automake libtool \
    libpopt-dev libconfig-dev libasound2-dev avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev \
    libplist-dev libsodium-dev uuid-dev libgcrypt-dev xxd libplist-utils \
    libavutil-dev libavcodec-dev libavformat-dev
}

# Build and install a repo: autoreconf, configure with the given args, make, make install.
build_install() {
  local dir="$1"; shift
  cd "$dir"
  autoreconf -fi
  ./configure "$@"
  make clean >/dev/null 2>&1 || true
  make
  sudo make install
}

# Skip everything if a client is streaming, since a rebuild or restart would cut it off.
# Shairport Sync listens on 5000 (classic AirPlay) and 7000 (AirPlay 2).
airplay_active() {
  ss -Htn state established '( sport = :5000 or sport = :7000 )' | grep -q .
}

if airplay_active; then
  log "AirPlay session in progress; skipping update."
  exit 0
fi

mkdir -p "$SRC_DIR"
NQPTP_DIR="$SRC_DIR/nqptp"
SHAIRPORT_DIR="$SRC_DIR/shairport-sync"

nqptp_changed=0
shairport_changed=0
update_repo https://github.com/mikebrady/nqptp.git "$NQPTP_DIR" && nqptp_changed=1 || true
update_repo https://github.com/mikebrady/shairport-sync.git "$SHAIRPORT_DIR" && shairport_changed=1 || true

if [[ $nqptp_changed -eq 0 && $shairport_changed -eq 0 ]]; then
  log "Nothing to do."
  exit 0
fi

install_deps

if [[ $nqptp_changed -eq 1 ]]; then
  log "Building NQPTP"
  build_install "$NQPTP_DIR" --with-systemd-startup
fi

if [[ $shairport_changed -eq 1 ]]; then
  log "Building Shairport Sync"
  build_install "$SHAIRPORT_DIR" \
    --sysconfdir=/etc --with-alsa \
    --with-soxr --with-avahi --with-ssl=openssl --with-systemd-startup --with-airplay-2
fi

log "Reloading systemd and restarting services"
sudo systemctl daemon-reload
# try-restart only restarts units that are currently running, so it is safe if one is stopped.
# NQPTP goes first, since Shairport Sync depends on it.
sudo systemctl try-restart nqptp
sudo systemctl try-restart shairport-sync

log "Done. Installed versions:"
nqptp -V || true
shairport-sync -V || true
