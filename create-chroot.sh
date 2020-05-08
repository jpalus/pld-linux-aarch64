#!/bin/sh

log() {
  echo "$@" >> "$LOG_FILE"
}

error() {
  echo "ERROR: $*" | tee -a "$LOG_FILE" >&2
  exit 1
}

run_log() {
  local msg="$1"; shift
  log "Running $@"
  echo -n "$msg..."
  "$@" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    echo "OK"
  else
    echo "FAILED"
    error "Command failed: $@"
  fi
}

run_log_priv() {
  local msg="$1"; shift
  run_log "$msg" $SUDO "$@"
}

if [ "$EUID" != "0" ]; then
  echo "Non-root user detected, using sudo"
  SUDO="sudo"
fi


SCRIPT_DIR=$(dirname $(readlink -f "$0"))
TIMESTAMP=$(date +%Y%m%d)
RELEASE_NAME="pld-linux-base-aarch64-$TIMESTAMP"
LOG_FILE="$SCRIPT_DIR/$RELEASE_NAME.log"
echo "Creating release $RELEASE_NAME"

CHROOT_DIR="$(mktemp -t -d $RELEASE_NAME.XXXXXXXXXX)"
if [ $? -ne 0 ]; then
  error 'failed to create temporary chroot directory'
fi

: > "$LOG_FILE"
echo "Logging to $LOG_FILE"

run_log_priv "Setting up temporary chroot in $CHROOT_DIR" rpm --initdb --root "$CHROOT_DIR"
run_log_priv "Installing packages from $SCRIPT_DIR/base.pkgs" poldek -iv --pset="$SCRIPT_DIR/base.pkgs" --root="$CHROOT_DIR" --noask
run_log_priv "Adjusting poldek repository configuration" sed -i -e '/^_prefix = / a _aarch64_prefix = http://jpalus.fastmail.com.user.fm/dists/th' -e 's|%{_prefix}/PLD/%{_arch}/RPMS|%{_aarch64_prefix}/PLD/%{_arch}/RPMS|' "$CHROOT_DIR/etc/poldek/repos.d/pld.conf"
rpm --root="$CHROOT_DIR" -qa|sort > "$SCRIPT_DIR/$RELEASE_NAME.packages"
run_log_priv "Creating archive $SCRIPT_DIR/$RELEASE_NAME.tar.xz" tar -Jcpf "$SCRIPT_DIR/$RELEASE_NAME.tar.xz" -C "$CHROOT_DIR" .

if [ "$EUID" != "0" ]; then
  run_log_priv "Changing ownership of $RELEASE_NAME.tar.xz" chown $USER "$SCRIPT_DIR/$RELEASE_NAME.tar.xz"
fi

run_log 'Signing' gpg --sign --armor --detach-sig "$SCRIPT_DIR/$RELEASE_NAME.tar.xz"
run_log_priv 'Cleaning up' rm -rf "$CHROOT_DIR"