SVC_NAME="$1"
if [[ -z "$SVC_NAME" ]]; then
    echo "Error: SVC_NAME is not set. Pass it as an argument."
    exit 1
fi

if id "$SVC_NAME" > /dev/null 2>&1; then
    echo "User $SVC_NAME already exists. Nothing to do."
else
    echo "Creating user $SVC_NAME..."
    useradd -r -m -s /usr/sbin/nologin "$SVC_NAME"
    echo "User $SVC_NAME created."
fi


echo "--- User details ---"
id "$SVC_NAME"
getent passwd "$SVC_NAME"