#!/bin/bash

export PATH=$PATH:/usr/sbin:/sbin

# Use Python to bring up network interfaces (avoids dependency on ip/iproute2)
ifup() {
    local iface="$1"
    python3 -c "
import socket, struct, fcntl
SIOCGIFFLAGS, SIOCSIFFLAGS, IFF_UP = 0x8913, 0x8914, 0x1
iface = b'$iface'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
flags = struct.unpack_from('<H', fcntl.ioctl(s, SIOCGIFFLAGS, struct.pack('16sH', iface, 0)), 16)[0]
fcntl.ioctl(s, SIOCSIFFLAGS, struct.pack('16sH', iface, flags | IFF_UP))
s.close()
print('  $iface is up')
" 2>&1
}

ifdel() {
    local iface="$1"
    python3 -c "
import socket, struct, fcntl
SIOCSIFFLAGS, IFF_UP = 0x8914, 0x1
iface = b'$iface'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    fcntl.ioctl(s, SIOCSIFFLAGS, struct.pack('16sH', iface, 0))
except:
    pass
s.close()
" 2>/dev/null || true
}

echo "🤖 Waking up the robot..."

# 0. Install System Dependencies
echo "Installing system dependencies..."
# Fix ROS 2 GPG key if needed
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
apt-get update
apt-get install -y libfmt-dev libcap-dev can-utils iproute2

# 1. Fix the "blinker" conflict (Force reinstall)
echo "Installing Python dependencies..."
pip install flask --ignore-installed blinker

# 2. CAN and robot tooling dependencies
pip install python-can

# 3. Bring up CAN interfaces — find ttyACM device by USB serial via udevadm
#    Serial 205D307F3541 → can0  (first CANable2)
#    Serial 208836774B34 → can1  (second CANable2)
echo "Bringing up CAN interfaces..."

find_tty_by_serial() {
    local target="$1"
    for tty in /sys/class/tty/ttyACM*; do
        serial_file="$(realpath $tty/device)/../serial"
        serial=$(cat "$serial_file" 2>/dev/null)
        if [ "$serial" = "$target" ]; then
            echo "/dev/$(basename $tty)"
            return 0
        fi
    done
    return 1
}

bring_up_can() {
    local iface="$1"
    local serial="$2"
    local dev
    dev=$(find_tty_by_serial "$serial")
    if [ -z "$dev" ]; then
        echo "  WARNING: no ttyACM device found with serial $serial — is the CANable2 plugged in?"
        return 1
    fi
    echo "  Found serial $serial → $dev"
    pkill -f "slcand.*$(basename $dev)" 2>/dev/null || true
    sleep 0.3
    ifdel "$iface"
    slcand -o -s8 -t hw -S 3000000 "$dev" "$iface"
    sleep 0.3
    ifup "$iface"
    echo "  $iface up ($dev → $iface)"
}

bring_up_can can0 205D307F3541
bring_up_can can1 208836774B34

echo "✅ Ready to rock! Don't forget to source ROS:"
echo "source ~/ros2_ws/install/setup.bash"
