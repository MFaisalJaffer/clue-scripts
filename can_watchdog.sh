#!/bin/bash

# CANable2 serial numbers → CAN interface mapping
# Serial 205D307F3541 → can0  (left leg)
# Serial 208836774B34 → can1  (right leg)

find_tty_by_serial() {
    local target="$1"
    for tty in /sys/class/tty/ttyACM*; do
        serial_file="$(realpath $tty/device 2>/dev/null)/../serial"
        serial=$(cat "$serial_file" 2>/dev/null)
        if [ "$serial" = "$target" ]; then
            echo "/dev/$(basename $tty)"
            return 0
        fi
    done
    return 1
}

ensure_can_up() {
    local iface="$1"
    local serial="$2"

    if ip link show "$iface" > /dev/null 2>&1; then
        if ! ip link show "$iface" | grep -q "UP"; then
            ip link set "$iface" up
        fi
    else
        local dev
        dev=$(find_tty_by_serial "$serial")
        if [ -n "$dev" ]; then
            echo "$(date): $iface missing — creating on $dev (serial $serial)..."
            pkill -f "slcand.*$(basename $dev)" 2>/dev/null || true
            sleep 0.3
            slcand -o -c -s6 "$dev" "$iface"
            sleep 0.5
            ip link set "$iface" up
            ip link set "$iface" txqueuelen 1000
            echo "$(date): $iface created."
        fi
    fi
}

while true; do
    ensure_can_up can0 205D307F3541
    ensure_can_up can1 208836774B34
    sleep 3
done
