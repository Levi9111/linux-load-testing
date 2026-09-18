#!/bin/bash

SVC_NAME="$1"
FLAG="$2"
TMPDIR="/mnt/${SVC_NAME}_tmp"

if [[ -z "$SVC_NAME" || -z "$FLAG" ]]; then
    echo "Usage: $0 <service-name> {--cpu|--mem|--disk|--all}"
    exit 1
fi

stress_cpu() {
    sudo -u "$SVC_NAME" stress-ng --cpu 2 --timeout 30s --temp-path /tmp
}

stress_mem() {
    sudo -u "$SVC_NAME" stress-ng --vm 1 --vm-bytes 200M --timeout 30s --temp-path /tmp
}

stress_disk() {
    for i in $(seq 1 30); do
        dd if=/dev/urandom of="$TMPDIR/file_$i.dat" bs=1M count=10 status=none
        df -h "$TMPDIR"
    done
}

stress_all() {
    stress_cpu &
    stress_mem &
    stress_disk &
    wait
}

case "$FLAG" in
    --cpu)  stress_cpu ;;
    --mem)  stress_mem ;;
    --disk) stress_disk ;;
    --all)  stress_all ;;
    *)      echo "Unknown flag: $FLAG"; exit 1 ;;
esac