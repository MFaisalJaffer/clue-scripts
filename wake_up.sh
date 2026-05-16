#!/bin/bash

echo "🤖 Waking up the robot..."

# 0. Install System Dependencies
echo "Installing system dependencies..."
# Fix ROS 2 GPG key if needed
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
apt-get update
apt-get install -y libfmt-dev libcap-dev can-utils

# 1. Fix the "blinker" conflict (Force reinstall)
echo "Installing Python dependencies..."
pip install flask --ignore-installed blinker

# 2. CAN and robot tooling dependencies
pip install python-can

# 3. Bring up CAN interfaces — use /dev/serial/by-id symlinks (persistent by USB serial)
#    Serial 205D307F3541 → can0  (first CANable2)
#    Serial 208836774B34 → can1  (second CANable2)
echo "Bringing up CAN interfaces..."

CANABLE0="/dev/serial/by-id/usb-Openlight_Labs_CANable2_b158aa7_github.com_normaldotcom_canable2.git_205D307F3541-if00"
CANABLE1="/dev/serial/by-id/usb-Openlight_Labs_CANable2_b158aa7_github.com_normaldotcom_canable2.git_208836774B34-if00"

bring_up_can() {
    local iface="$1"
    local dev="$2"
    if [ ! -e "$dev" ]; then
        echo "  WARNING: $dev not found — is the CANable2 plugged in?"
        return 1
    fi
    pkill -f "slcand.*$(basename $(readlink -f $dev))" 2>/dev/null || true
    sleep 0.3
    ip link delete "$iface" 2>/dev/null || true
    slcand -o -s8 -t hw -S 3000000 "$dev" "$iface"
    sleep 0.3
    ip link set "$iface" up
    echo "  $iface up ($dev)"
}

bring_up_can can0 "$CANABLE0"
bring_up_can can1 "$CANABLE1"

echo "✅ Ready to rock! Don't forget to source ROS:"
echo "source ~/ros2_ws/install/setup.bash"
