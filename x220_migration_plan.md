# Migration Plan: Forecr DSBOARD-AGX-MIIM → Auvidea X220

**Project:** Humanoid robotics platform — Jetson AGX Xavier 64GB compute
**Module:** NVIDIA Jetson AGX Xavier 64GB (900-82888-0050) — unchanged
**Author:** Faisal
**Status:** Planning

---

## 1. Why migrate

The Forecr DSBOARD-AGX-MIIM rev 1.1 is a custom Forecr variant with no publicly available pinout documentation, schematic, or connector definition. This has blocked:

- Connecting a 3.3V IMU (BNO08x) — unknown which headers are safe / what logic voltage
- Identifying the function of the 3-pin TX/RX/GND header next to the debug connector
- Identifying the pins exposed under the M.2 NVMe slot
- Any sensor / peripheral integration beyond what's pre-wired

The Auvidea X220 is a documented, catalog AGX Xavier carrier with a published technical reference manual, downloadable firmware overlays for current JetPack versions, and a Software Setup Guide. Migration eliminates the documentation blocker and unlocks the rest of the build.

---

## 2. Current state (Forecr DSBOARD-AGX-MIIM)

| Item | Detail |
|---|---|
| Carrier board | Forecr DSBOARD-AGX-MIIM rev 1.1 (S/N BRDAGXMIIM-243 and BRDAGXMIIM-177) |
| Module | Jetson AGX Xavier 64GB (900-82888-0050) |
| Storage | PNY CS2241 M.2 NVMe SSD |
| OS / JetPack | JetPack 5.1.3 (current install) |
| CAN connectivity | External USB-to-CAN (CANable clones via powered USB hub) |
| Kernel | PREEMPT_RT (added to compensate for USB-to-CAN jitter) |
| Documented headers | None — silkscreen-only identification |
| Identified headers | 12-pin (3×4) PWM/+5V/GND × channels 0–3 servo output header; 3-pin TX/RX/GND debug header (unconfirmed function) |
| Power input | 48V battery pack (10,000 mAh) — handled by board's onboard regulation |

### Known unknowns on the miim board

- I²C / SPI breakout location and voltage level
- Whether the TX/RX/GND header is a free UART or console-only
- Pinout of the row exposed under the NVMe slot
- Whether 64GB-specific power/thermal considerations differ from 32GB

---

## 3. Target state (Auvidea X220)

| Item | Detail |
|---|---|
| Carrier board | Auvidea X220 (model 38339) |
| Module | Same — Jetson AGX Xavier 64GB |
| Storage | Same NVMe SSD — moves into X220's M.2 Key-M 2280 slot (PCIe x4) |
| OS / JetPack | JetPack 5.1.2 + Auvidea firmware overlay v2.0 (Dec 2023) |
| CAN connectivity | **Onboard — 3× native CAN buses** (CAN0/J12, CAN1/J6, CAN2/J5), each 4-pin JST-GH 1.25mm pitch, 120Ω terminated at board, 5V power available on bus |
| Kernel | Stock JetPack first; PREEMPT_RT only if control-loop measurement requires it |
| IMU | **MPU-9250 onboard 9-axis IMU** — ordered populated with the X220. No external IMU wiring, no level shifter needed. |
| Documentation | Full published technical reference manual + Software Setup Guide |
| Power input | 12V–48V (Rev 2+) via 5.5/2.5mm power jack — compatible with existing 48V pack |

### Why each change

- **CAN: USB → onboard** removes the USB transport jitter that originally forced PREEMPT_RT. Three native buses also let us split joints across buses for bandwidth headroom (left leg / right leg / arms+torso).
- **JetPack 5.1.3 → 5.1.2** to match Auvidea's published firmware overlay. JetPack 5.1.x is the Xavier ceiling regardless — no Orin-only JetPack 6 here.
- **PREEMPT_RT becomes optional** because the USB-to-CAN jitter source is gone. Only the control-loop scheduling jitter source remains. To be evaluated by measurement post-migration.
- **Documented connectors** unblock IMU integration and any future sensor work.

---

## 4. What carries over unchanged

- The Jetson AGX Xavier 64GB module itself — same form factor and connector across the AGX Xavier family
- The PNY CS2241 NVMe SSD (will need re-flash, but hardware moves)
- The 48V battery pack and existing power distribution (X220 accepts 12–48V on Rev 2+)
- All ROS / robot application code (re-installed on the fresh JetPack image)
- GIM 8108-8 motor controllers and their CAN wiring — only the *bus endpoint* changes (USB dongle → onboard JST-GH connectors)

---

## 5. What needs to change / be acquired

### Hardware to acquire

- [x] Auvidea X220 carrier board **with MPU-9250 IMU populated** — ordered
- [ ] 4-pin JST-GH 1.25mm pigtail cables × 3 (one per CAN bus) — to interface motors to onboard CAN
- [ ] 5.5/2.5mm power jack pigtail — to feed 48V from existing pack into X220's J1

### Software / config to redo

- [ ] Fresh flash with JetPack 5.1.2 + Auvidea overlay (clean install — not an upgrade)
- [ ] Reinstall ROS distribution and all robot application code
- [ ] Reinstall JetPack components (CUDA, cuDNN, TensorRT)
- [ ] Reconfigure SocketCAN for 3× native CAN buses (`can0`, `can1`, `can2`) instead of USB-CAN device names
- [ ] Re-allocate joints across the 3 CAN buses (planning task — see §8)
- [ ] *(If needed)* Rebuild kernel with PREEMPT_RT against L4T 35.4.1 sources

### What gets removed

- USB-to-CAN dongles (CANable clones)
- Powered USB hub for CAN dongles
- Any udev rules / scripts tied to USB-CAN device persistence

---

## 6. Pre-migration: open questions for Auvidea

To send before / alongside the order. Email: support / sales contact via auvidea.eu.

1. Confirm the **Auvidea X220 (model 38339)** supports the **NVIDIA Jetson AGX Xavier 64GB module (900-82888-0050)**, including any thermal or power considerations specific to the 64GB variant.
2. Confirm the **Dec 2023 firmware v2.0 (JetPack 5.1.2)** from the firmware page covers the AGX Xavier 64GB module on the X220 (the description names the X220 explicitly but does not call out "64GB" specifically the way the older v4.1 entry does).
3. Confirm availability of the **paid flashing service** for the X220 + Xavier 64GB combination, as a fallback to self-flashing.
4. Confirm which I²C bus and address the onboard **MPU-9250** appears on under the Auvidea-overlay JetPack 5.1.2 image, and whether a device-tree entry is already enabled or needs to be added.

---

## 7. Migration procedure

### Phase A — Preparation (before touching hardware)

1. **Back up the current miim setup**
   - Image the NVMe (`dd` to a file on a host machine, or clone with Clonezilla)
   - Export current ROS configs, CAN setup scripts, and any robot-specific calibration data
   - Document current network/IP configuration
2. **Prepare host PC**
   - x86 machine running Ubuntu 20.04 LTS
   - Install NVIDIA SDK Manager
   - At least 50 GB free disk space
3. **Download firmware**
   - From NVIDIA SDK Manager: select Xavier AGX target + JetPack 5.1.2 → download **Jetson OS only**, skip flashing, close SDK Manager. This produces `~/nvidia/nvidia_sdk/.../Linux_for_Tegra/`.
   - From `auvidea.eu/firmware/`: download the **Dec 2023 v2.0** firmware for JetPack 5.1.2 (~57 KB)
   - Also download the linked **Software Setup Guide** PDF from the same row
4. **Apply Auvidea overlay**
   - Follow the Software Setup Guide exactly — the general pattern is: extract the firmware archive, copy/patch into `Linux_for_Tegra/`, run `sudo ./apply_binaries.sh`. The guide will have the precise commands.

### Phase B — Hardware swap

5. **Power down everything**. Disconnect the 48V battery from the miim board.
6. **Remove the Xavier 64GB module from the miim board.** Note thermal interface material condition — replace TIM if it looks degraded.
7. **Remove the NVMe SSD** from the miim board.
8. **Install the Xavier module into the X220's SoM connector.** Torque mounting screws to spec. Reinstall thermal solution.
9. **Install the NVMe into the X220's M.2 Key-M slot (J9 / J15 depending on revision).**
10. **Wire power**: 48V pack → 5.5/2.5mm jack → X220 J1 (center pin positive). Verify polarity twice before applying power.

### Phase C — First flash

11. **Connect host PC to X220** via USB-C / micro-USB (recovery / OTG port — check the board's USB 2.0 connector marked for firmware upgrades).
12. **Power on the X220.** The X220 supports auto-flash: the onboard MCU detects the OTG connection at power-up and enters recovery mode automatically — no recovery button needed.
13. **Run the flash command** from the modified `Linux_for_Tegra/` directory. Exact command per Auvidea's Software Setup Guide — typically `sudo ./flash.sh <board_name> mmcblk0p1` or similar.
14. **First boot.** Complete Ubuntu OOBE. Verify with:
    ```bash
    cat /etc/nv_tegra_release    # confirm L4T version
    lsblk                        # confirm NVMe is detected
    ip a                         # confirm Ethernet
    ```

### Phase D — CAN bring-up

15. **Wire CAN.** Crimp three 4-pin JST-GH pigtails. Connect motors per the joint-to-bus plan (§8). Daisy-chain each bus, terminate the last motor on each bus with 120Ω (the X220 already terminates the board end).
16. **Configure SocketCAN**:
    ```bash
    sudo ip link set can0 up type can bitrate 1000000
    sudo ip link set can1 up type can bitrate 1000000
    sudo ip link set can2 up type can bitrate 1000000
    ```
17. **Verify with can-utils**:
    ```bash
    sudo apt install can-utils
    candump can0    # in one terminal
    cansend can0 123#DEADBEEF    # in another, to test loopback or sniff motor traffic
    ```
18. **Make CAN config persistent** via systemd-networkd or a startup script.

### Phase D2 — IMU bring-up

The robot policy consumes only two IMU-derived signals:
- `imu_gyro_3` — 3-axis angular velocity (ω) in the body frame, rad/s
- `projected_gravity_3` — gravity vector expressed in the body frame ("which way is down")

This is the Isaac Lab / Isaac Gym humanoid convention (yaw-invariant by construction). It means **no magnetometer is needed and no full sensor fusion / EKF is needed.** The magnetometer is left unused — the MPU-9250's biggest weakness (mag distortion from motors and high-current cabling) becomes irrelevant.

19. **Detect the MPU-9250 on I²C**:
    ```bash
    sudo i2cdetect -y -r <bus>    # bus number per Auvidea Q4 answer
    ```
    Expect address 0x68 (or 0x69 if AD0 is strapped high) for the accel/gyro die. The AK8963 magnetometer (0x0C) is irrelevant for this setup.
20. **Configure the IMU.** Internal sample rate 200–1000 Hz, accel range ±4g or ±8g (humanoid acceleration peaks well under 4g), gyro range ±1000 °/s (covers limb swing), DLPF enabled to suppress motor-vibration noise. Magnetometer disabled or simply not read.
21. **Run `imu_filter_madgwick` in 6-DOF mode** (`use_mag: false`). Subscribe to raw accel + gyro, publish fused orientation quaternion. This handles the periods when the robot is accelerating and the accelerometer alone would not be a reliable gravity reference.
22. **Build the policy-input node** (small ROS node or rolled into your existing policy interface):
    - `imu_gyro_3` ← bias-corrected gyro, possibly very lightly low-passed, in **body frame**
    - `projected_gravity_3` ← rotate world gravity `[0, 0, -1]` (or `[0, 0, -9.81]` — match policy convention) into body frame using the inverse of the Madgwick quaternion
23. **Calibrate (minimal):**
    - **Gyro bias zeroing on startup** — hold robot still for ~2 s at boot, average gyro reading, subtract. Critical: even small bias becomes a constant offset the policy will learn around poorly.
    - **Accel one-time check** — verify ||accel|| ≈ 9.81 m/s² when stationary; apply scale correction if off.
    - **No magnetometer calibration.** Skipped entirely.
24. **Verify IMU-to-body frame alignment.** The MPU-9250 has its own X/Y/Z axes; Auvidea mounts the chip in some orientation on the X220, which puts those axes in some orientation relative to the robot body. Determine the rotation matrix from IMU frame to body frame:
    - Tilt the robot forward → expect pitch on the policy's pitch axis with the correct sign
    - Tilt right → expect roll on the policy's roll axis with the correct sign
    - Yaw rotate → expect yaw on the policy's yaw axis with the correct sign
    - Apply the IMU→body transform to both `imu_gyro_3` and `projected_gravity_3`
25. **Convention check before any policy rollout:**
    - Is `projected_gravity_3` expected as a unit vector or in m/s²?
    - Is "down" expressed as negative Z or positive Z in the policy's frame?
    - Mismatched conventions cause subtle failures — confirm by holding the robot in known poses and printing the values.
26. **Verify policy input rate.** Locomotion policies typically expect 50–200 Hz. Run Madgwick at the higher IMU rate (200–500 Hz), downsample to the policy rate at the policy interface — do not run Madgwick at the policy rate, it loses accuracy.

### Phase E — Software stack rebuild

27. **Install JetPack components** (CUDA, cuDNN, TensorRT) via SDK Manager's "Install on Target" against the booted X220.
28. **Install ROS distribution** (matching what the miim setup used).
29. **Pull and rebuild robot application code.**
30. **Reconfigure CAN-using nodes**: change device names from USB-CAN aliases to `can0`/`can1`/`can2`.
31. **Integrate IMU node** with the policy interface (publishing `imu_gyro_3` and `projected_gravity_3` per §D2).

### Phase F — RT decision

32. **Run the actual control loop on the stock JetPack kernel first.**
33. **Measure cycle jitter** during representative motion:
    - `cyclictest -p 80 -t -n -i 1000 -l 100000` for raw scheduling jitter
    - Application-level: log timestamps of each control cycle, plot the distribution of cycle periods
34. **Decide:**
    - If max jitter is well within control tolerance → **skip PREEMPT_RT**, ship stock.
    - If jitter intrudes into control budget → **build PREEMPT_RT kernel** against L4T 35.4.1, re-flash.

---

## 8. CAN bus allocation plan

The X220 provides 3 native CAN buses. Recommended split for a humanoid (refine when joint count is finalized):

| Bus | Connector | Assigned joints (proposed) |
|---|---|---|
| can0 | J12 | Left leg — hip yaw/roll/pitch, knee, ankle pitch/roll |
| can1 | J6 | Right leg — same set as left |
| can2 | J5 | Arms + torso + head |

Each bus at 1 Mbit/s. Per-joint frame budget at 500 Hz outer loop ≈ ~120 bits per direction × N joints × 500 Hz must stay under bus capacity with headroom for retries and acknowledgments. Confirm per-motor frame size from the GIM 8108-8 controller protocol once finalized.

---

## 9. IMU sensor fusion implementation (ROS 2)

Detailed walkthrough of the IMU → policy pipeline outlined in Phase D2. Policy consumes `imu_gyro_3` and `projected_gravity_3` only — no magnetometer, no EKF.

### 9.1 Pipeline overview

```
MPU-9250 (I²C, addr 0x68)
    │  raw accel + gyro at 200–500 Hz
    ▼
[mpu9250_node]  ── publishes /imu/data_raw (sensor_msgs/Imu, no orientation)
    │
    ▼
[imu_filter_madgwick]  ── 6-DOF mode, fuses accel+gyro → orientation quaternion
    │  publishes /imu/data (sensor_msgs/Imu with orientation)
    ▼
[policy_input_node]  ── extracts gyro, rotates world gravity into body frame
    │  publishes /policy/imu_gyro_3 and /policy/projected_gravity_3
    ▼
[robot policy node]
```

Three nodes. The middle node is off-the-shelf (`imu_filter_madgwick`); the first and third are written for this project. Keeping them separate makes each independently debuggable.

### 9.2 Node 1 — MPU-9250 driver

**Purpose:** Read accel + gyro registers over I²C, scale to SI, publish at fixed rate.

Three implementation options:

| Option | Effort | Notes |
|---|---|---|
| Existing ROS 2 driver | Low if one exists for current distro | Audit before trusting — quality varies. Search `ros2_mpu9250_driver` on GitHub. |
| Hand-rolled Python node | Medium | ~150 lines. Easiest to get exactly the rate, bias correction, and axis remapping needed. Recommended for bring-up. |
| Kernel IIO (`inv_mpu6050`) → ROS 2 node | Medium-high | Cleaner if the kernel driver is enabled in Auvidea's overlay; adds a sysfs layer. |

**Hand-rolled Python sketch** (functional starting point, ~150 lines):

```python
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu
from smbus2 import SMBus
import struct, time

MPU_ADDR     = 0x68
PWR_MGMT_1   = 0x6B
ACCEL_XOUT_H = 0x3B   # 14 bytes from here: ax,ay,az,temp,gx,gy,gz (each int16 BE)
GYRO_CONFIG  = 0x1B
ACCEL_CONFIG = 0x1C
CONFIG       = 0x1A   # DLPF
SMPLRT_DIV   = 0x19

class MPU9250Node(Node):
    def __init__(self):
        super().__init__('mpu9250_node')
        self.bus = SMBus(1)           # ← set to the I²C bus number from i2cdetect
        self.pub = self.create_publisher(Imu, '/imu/data_raw', 50)

        # Wake up + configure
        self.bus.write_byte_data(MPU_ADDR, PWR_MGMT_1,  0x01)  # PLL with X gyro reference
        self.bus.write_byte_data(MPU_ADDR, CONFIG,      0x03)  # DLPF ~41 Hz, internal rate 1 kHz
        self.bus.write_byte_data(MPU_ADDR, SMPLRT_DIV,  0x04)  # 1 kHz / (1+4) = 200 Hz output
        self.bus.write_byte_data(MPU_ADDR, GYRO_CONFIG, 0x10)  # ±1000 °/s, scale 32.8 LSB/(°/s)
        self.bus.write_byte_data(MPU_ADDR, ACCEL_CONFIG,0x08)  # ±4 g, scale 8192 LSB/g

        # Gyro bias calibration — robot MUST be still
        self.get_logger().info('Calibrating gyro bias — hold robot still...')
        time.sleep(0.5)
        N = 400
        bx = by = bz = 0
        for _ in range(N):
            _,_,_, gx, gy, gz = self._read_raw()
            bx += gx; by += gy; bz += gz
            time.sleep(0.005)
        self.gyro_bias = (bx/N, by/N, bz/N)
        self.get_logger().info(f'Gyro bias: {self.gyro_bias}')

        self.timer = self.create_timer(1.0/200.0, self.tick)

    def _read_raw(self):
        data = self.bus.read_i2c_block_data(MPU_ADDR, ACCEL_XOUT_H, 14)
        ax, ay, az, _t, gx, gy, gz = struct.unpack('>hhhhhhh', bytes(data))
        return ax, ay, az, gx, gy, gz

    def tick(self):
        ax, ay, az, gx, gy, gz = self._read_raw()
        accel_scale = 9.80665 / 8192.0                   # m/s² per LSB
        gyro_scale  = (3.14159265 / 180.0) / 32.8        # rad/s per LSB
        ax *= accel_scale; ay *= accel_scale; az *= accel_scale
        gx = (gx - self.gyro_bias[0]) * gyro_scale
        gy = (gy - self.gyro_bias[1]) * gyro_scale
        gz = (gz - self.gyro_bias[2]) * gyro_scale

        msg = Imu()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'imu_link'
        msg.orientation_covariance[0] = -1.0             # signal "no orientation"
        msg.linear_acceleration.x = ax
        msg.linear_acceleration.y = ay
        msg.linear_acceleration.z = az
        msg.angular_velocity.x = gx
        msg.angular_velocity.y = gy
        msg.angular_velocity.z = gz
        # Diagonal covariances — tune from observed noise floor
        for i in (0, 4, 8):
            msg.linear_acceleration_covariance[i] = 0.01
            msg.angular_velocity_covariance[i]    = 0.001
        self.pub.publish(msg)

def main():
    rclpy.init()
    rclpy.spin(MPU9250Node())

if __name__ == '__main__':
    main()
```

**Caveats:** Timer-driven I²C in Python has jitter. If actual publish rate is unstable, switch to C++ or use the MPU-9250's FIFO + interrupt path. For initial bring-up, Python is fine.

### 9.3 Node 2 — Madgwick fusion (6-DOF mode)

**Purpose:** Fuse accel + gyro into an orientation quaternion. Magnetometer disabled.

Install:
```bash
sudo apt install ros-humble-imu-filter-madgwick    # match your ROS 2 distro
```

Launch config:
```python
Node(
    package='imu_filter_madgwick',
    executable='imu_filter_madgwick_node',
    name='imu_filter',
    parameters=[{
        'use_mag':     False,    # 6-DOF — yaw can drift, doesn't matter for projected gravity
        'world_frame': 'enu',    # or 'nwu', match policy convention
        'publish_tf':  False,
        'gain':        0.1,      # tune: lower = trust gyro more, higher = trust accel more
    }],
    remappings=[
        ('imu/data_raw', '/imu/data_raw'),
        ('imu/data',     '/imu/data'),
    ],
)
```

`gain` is the only knob worth tuning. Start at 0.1. If orientation lags during fast motion, raise slightly. If it's twitchy when stationary, lower.

### 9.4 Node 3 — Policy input node

**Purpose:** Convert `/imu/data` into the two signals the policy consumes.

```python
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu
from geometry_msgs.msg import Vector3Stamped
import numpy as np

# IMU-to-body rotation. Identity until empirical alignment check (Phase D2 step 24).
R_imu_to_body = np.eye(3)

# World gravity in policy convention. CONFIRM with policy spec:
#   - unit vector or m/s²?
#   - "down" = -Z or +Z?
G_WORLD = np.array([0.0, 0.0, -1.0])    # unit vector, Z-up world (typical Isaac Lab)

def quat_to_rotmat(q):
    # q = [x, y, z, w] (ROS convention)
    x, y, z, w = q
    return np.array([
        [1-2*(y*y+z*z),   2*(x*y - z*w),   2*(x*z + y*w)],
        [2*(x*y + z*w),   1-2*(x*x+z*z),   2*(y*z - x*w)],
        [2*(x*z - y*w),   2*(y*z + x*w),   1-2*(x*x+y*y)],
    ])

class PolicyInputNode(Node):
    def __init__(self):
        super().__init__('policy_input_node')
        self.sub = self.create_subscription(Imu, '/imu/data', self.cb, 50)
        self.pub_gyro = self.create_publisher(Vector3Stamped, '/policy/imu_gyro_3', 50)
        self.pub_grav = self.create_publisher(Vector3Stamped, '/policy/projected_gravity_3', 50)

    def cb(self, msg: Imu):
        # 1) imu_gyro_3 — gyro is in IMU frame; rotate into body frame
        gyro_imu  = np.array([msg.angular_velocity.x,
                              msg.angular_velocity.y,
                              msg.angular_velocity.z])
        gyro_body = R_imu_to_body @ gyro_imu

        # 2) projected_gravity_3 — express world gravity in body frame
        #    Madgwick quaternion is body→world. g_body = R_body_to_world.T @ g_world
        q = [msg.orientation.x, msg.orientation.y,
             msg.orientation.z, msg.orientation.w]
        R_body_to_world = quat_to_rotmat(q)
        g_in_imu  = R_body_to_world.T @ G_WORLD
        g_body    = R_imu_to_body @ g_in_imu

        m1 = Vector3Stamped(); m1.header = msg.header
        m1.vector.x = float(gyro_body[0])
        m1.vector.y = float(gyro_body[1])
        m1.vector.z = float(gyro_body[2])
        self.pub_gyro.publish(m1)

        m2 = Vector3Stamped(); m2.header = msg.header
        m2.vector.x = float(g_body[0])
        m2.vector.y = float(g_body[1])
        m2.vector.z = float(g_body[2])
        self.pub_grav.publish(m2)

def main():
    rclpy.init()
    rclpy.spin(PolicyInputNode())
```

**Frames are the easy-to-get-wrong part.** Madgwick's quaternion is body→world; gravity-in-body needs the transpose. Verify with a static tilt test before connecting the policy.

### 9.5 Launch file

```python
# launch/imu_pipeline.launch.py
from launch import LaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    return LaunchDescription([
        Node(package='your_pkg', executable='mpu9250_node',     name='mpu9250'),
        Node(
            package='imu_filter_madgwick',
            executable='imu_filter_madgwick_node',
            name='imu_filter',
            parameters=[{'use_mag': False, 'gain': 0.1, 'publish_tf': False}],
        ),
        Node(package='your_pkg', executable='policy_input_node', name='policy_input'),
    ])
```

Run:
```bash
ros2 launch your_pkg imu_pipeline.launch.py
```

### 9.6 Verification checks (run in this order)

Do not connect the policy until all six pass.

1. **Raw data sane?**
   ```bash
   ros2 topic echo /imu/data_raw --once
   ```
   Stationary: `||linear_acceleration||` ≈ 9.81 m/s², `angular_velocity` ~ 0 (post-bias-zeroing).

2. **Fusion converging?**
   ```bash
   ros2 topic echo /imu/data
   ```
   Upright stationary: quaternion near identity. Tilt: smooth quaternion change.

3. **Gravity vector correct?**
   ```bash
   ros2 topic echo /policy/projected_gravity_3
   ```
   Upright: ≈ `[0, 0, -1]` (or `[0, 0, +1]` per convention). Tilt forward 45°: ≈ `[0.707, 0, -0.707]` if forward = +X. Signs/axes wrong → fix `R_imu_to_body` and/or `G_WORLD` sign.

4. **Gyro correct?**
   ```bash
   ros2 topic echo /policy/imu_gyro_3
   ```
   Yaw left at ~1 rad/s by hand: ~+1 on Z. Pitch up: rotation on pitch axis. Etc.

5. **Rate matches policy expectation?**
   ```bash
   ros2 topic hz /policy/imu_gyro_3
   ```
   Target rate (50–200 Hz). Hitching → Python I²C bottleneck; switch to C++.

6. **Latency reasonable?** Few ms from physical motion to topic update. Timestamp deltas or LED-and-scope test if it matters for your loop rate.

### 9.7 Implementation gotchas

- **Gyro bias zeroing requires the robot to actually be still.** Add a startup sanity check: if gyro magnitude during the cal window exceeds a threshold, abort and retry. Baking in bias from a moving robot gives a constant offset the policy must learn around.
- **Madgwick converges slowly from a wrong initial state.** First ~5 s after startup the orientation can be off. Gate the policy on "IMU stable" before allowing actions.
- **Motor vibration couples into the accelerometer.** The DLPF setting in §9.2 (`CONFIG = 0x03`, ~41 Hz cutoff) helps. If issues persist, lower the bandwidth or add software filtering.
- **`gain` is the main Madgwick knob.** Too low → orientation lags during motion. Too high → jitter from accel noise. Tune on representative motion.
- **Convention drift between sim and real.** If the policy was trained in Isaac Lab/Gym, mirror their exact convention: unit-vector gravity, Z-up world, ROS quaternion order `[x,y,z,w]` vs Isaac's `[w,x,y,z]` — these silently differ. Print values in known poses and match by inspection.

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Auvidea firmware doesn't actually support 64GB module despite generic "AGX Xavier" listing | Email Auvidea before purchase (Q1 in §6); fall back to v4.1 JetPack 4.6 firmware which explicitly names 64GB if needed |
| Flashing process fails (wrong JetPack version, missing overlay step) | Follow Auvidea Software Setup Guide exactly; have the option of Auvidea's paid flashing service as backup |
| X220 thermal solution insufficient for 64GB module under load | Verify thermal solution matches 64GB module power envelope (10W idle, up to 30W under load); add active cooling if needed |
| Stock kernel jitter still too high after removing USB-CAN | PREEMPT_RT remains an option — same procedure as on the miim board, just applied to the X220's L4T 35.4.1 base |
| Lost robot calibration / configs in re-flash | Phase A backups; keep miim board intact until X220 is verified working |
| MPU-9250 device-tree entry not enabled in Auvidea overlay → IMU invisible on I²C | Confirm with Auvidea (Q4 §6); add DT node manually against L4T 35.4.1 sources if needed |
| Gyro bias drift with temperature → constant offset in `imu_gyro_3` that policy must learn around | On-startup bias zeroing while robot is held still (~2 s); consider periodic re-zeroing during known-still episodes |
| IMU-to-body frame axis misalignment → policy sees rotated gyro and gravity, behaves badly | Empirical alignment check during Phase D2 step 24 (tilt-forward / tilt-right / yaw tests); apply rotation matrix at the policy interface |
| `projected_gravity_3` convention mismatch (unit vs m/s², sign of "down") → silent policy failure | Confirm against policy spec before any rollout (Phase D2 step 25); print values in known poses to verify |

---

## 11. Rollback plan

The miim board is not modified or discarded during this migration. If the X220 setup fails or is unrecoverable:

1. Remove the Xavier module from the X220.
2. Reinstall it on the miim board.
3. Restore the NVMe image taken in Phase A step 1, or re-flash the miim board's last working JetPack 5.1.3 image.
4. Reconnect the USB-to-CAN dongles and powered hub.

Total rollback time: under an hour assuming the backup image is good.

---

## 12. Open items to resolve before starting

- [ ] Send pre-migration questions to Auvidea (§6)
- [x] Confirm purchase: X220 board **with MPU-9250 populated** — ordered
- [ ] Order JST-GH crimps and 4-pin pigtails (3×) — or pre-made cables
- [ ] Order 5.5/2.5mm power jack pigtail for 48V input
- [ ] Finalize joint-to-CAN-bus allocation (§8) based on actual joint count
- [ ] Image current miim NVMe before any hardware move
- [ ] Decide: self-flash or pay Auvidea's flashing service
