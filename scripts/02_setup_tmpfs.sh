SVC_NAME="$1"
if [[ -z "$SVC_NAME" ]]; then
    echo "Error: SVC_NAME is not set. Pass it as an argument."
    exit 1
fi

MOUNT_DIR="/mnt/${SVC_NAME}_tmp"
echo "Setting up tmpfs at $MOUNT_DIR..."

mkdir -p "$MOUNT_DIR"

if mountpoint -q "$MOUNT_DIR"; then
    echo "$MOUNT_DIR is already mounted. Skipping mount."
else
    echo "Mounting tmpfs with 256M cap..."
    mount -t tmpfs -o size=256M tmpfs "$MOUNT_DIR"
fi

chown "$SVC_NAME":"$SVC_NAME" "$MOUNT_DIR"

echo "--- Mount details ---"
df -h "$MOUNT_DIR"
mount | grep "$MOUNT_DIR"