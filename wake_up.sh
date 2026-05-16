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

# 3. Pin CANable2 USB serial numbers to stable symlinks
#    canable0 → serial 205D307F3541 (→ can0)
#    canable1 → serial 208836774B34 (→ can1)
echo "Writing udev rules for CANable2 adapters..."
cat > /etc/udev/rules.d/99-canable.rules << 'EOF'
SUBSYSTEM=="tty", ATTRS{idVendor}=="16d0", ATTRS{idProduct}=="117e", ATTRS{serial}=="205D307F3541", SYMLINK+="canable0"
SUBSYSTEM=="tty", ATTRS{idVendor}=="16d0", ATTRS{idProduct}=="117e", ATTRS{serial}=="208836774B34", SYMLINK+="canable1"
EOF
udevadm control --reload-rules
udevadm trigger

# 4. Bring up CAN interfaces
echo "Bringing up CAN interfaces..."

# Kill any stale slcand processes for our devices
pkill -f "slcand.*canable0" 2>/dev/null || true
pkill -f "slcand.*canable1" 2>/dev/null || true
sleep 0.5

# can0 — first CANable2 (serial 205D307F3541)
if [ -e /dev/canable0 ]; then
    ip link delete can0 2>/dev/null || true
    slcand -o -s8 -t hw -S 3000000 /dev/canable0 can0
    ip link set can0 up
    echo "  can0 up (/dev/canable0)"
else
    echo "  WARNING: /dev/canable0 not found — is the first CANable2 plugged in?"
fi

# can1 — second CANable2 (serial 208836774B34)
if [ -e /dev/canable1 ]; then
    ip link delete can1 2>/dev/null || true
    slcand -o -s8 -t hw -S 3000000 /dev/canable1 can1
    ip link set can1 up
    echo "  can1 up (/dev/canable1)"
else
    echo "  WARNING: /dev/canable1 not found — is the second CANable2 plugged in?"
fi

echo "✅ Ready to rock! Don't forget to source ROS:"
echo "source ~/ros2_ws/install/setup.bash"
