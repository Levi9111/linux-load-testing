#!/bin/bash

SVC_NAME="$1"
if [[ -z "$SVC_NAME" ]]; then
    echo "Usage: $0 <service-name>"
    exit 1
fi

TMPDIR="/mnt/${SVC_NAME}_tmp"
LOGDIR="/var/log/$SVC_NAME"
MON="/usr/local/bin/${SVC_NAME}_monitor.sh"
CLEAN="/usr/local/bin/${SVC_NAME}_cleanup_old_files.sh"
LOGROTATE="/etc/logrotate.d/$SVC_NAME"

echo "=== Cleanup for $SVC_NAME ==="

# 1. Kill any processes owned by the service account
echo "[1/5] Killing processes..."
pkill -u "$SVC_NAME" 2>/dev/null || true

# 2. Remove automation
echo "[2/5] Removing automation..."
crontab -r -u "$SVC_NAME" 2>/dev/null || true
rm -f "$LOGROTATE"
rm -f "$MON"
rm -f "$CLEAN"

# 3. Unmount storage
echo "[3/5] Unmounting tmpfs..."
if mountpoint -q "$TMPDIR"; then
    umount "$TMPDIR" 2>/dev/null || umount -l "$TMPDIR" 2>/dev/null || true
fi
rmdir "$TMPDIR" 2>/dev/null || true

# 4. Remove logs
echo "[4/5] Removing logs..."
rm -rf "$LOGDIR"

# 5. Remove user
echo "[5/5] Removing service account..."
if id "$SVC_NAME" >/dev/null 2>&1; then
    userdel -r "$SVC_NAME" 2>/dev/null || true
fi

echo "=== Verification ==="
echo "-- id:"
id "$SVC_NAME" 2>&1 || true
echo "-- mounts:"
mount | grep "$SVC_NAME" || echo "  (no mounts)"
echo "-- processes:"
ps -u "$SVC_NAME" || echo "  (no processes)"
