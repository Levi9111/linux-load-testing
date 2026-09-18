#!/bin/bash

for i in $(seq 1 20); do
    dd if=/dev/urandom of="/mnt/${SVC_NAME}_tmp/file_$i.dat" bs=1M count=10
    df -h "/mnt/${SVC_NAME}_tmp"
done