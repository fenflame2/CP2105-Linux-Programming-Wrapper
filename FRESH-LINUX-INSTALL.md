# Fresh Linux Installation — CP2105 Wrapper v0.2b

This installs the serial-agnostic wrapper on a Debian or Ubuntu x86_64 host.
The wrapper accepts any non-empty CP2105 serial number detected at runtime, one
attached device at a time.

## 1. Install Git and clone the wrapper

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates git

mkdir -p "$HOME/work"
git clone \
    https://github.com/fenflame2/CP2105-Linux-Programming-Wrapper.git \
    "$HOME/work/CP2105-Linux-Programming-Wrapper"

cd "$HOME/work/CP2105-Linux-Programming-Wrapper"
```

Separately download the official Silicon Labs Linux SDK to `~/Downloads`:

```text
USBXpressHostSDK-6.7.7-Linux.tar.gz
```

Official source:

https://www.silabs.com/interface/usb-bridges/classic/device.cp2105

## 2. Verify the wrapper and official SDK

```bash
cd "$HOME/work/CP2105-Linux-Programming-Wrapper"
sha256sum --check SHA256SUMS

cd "$HOME/Downloads"
sha256sum USBXpressHostSDK-6.7.7-Linux.tar.gz
```

Every `SHA256SUMS` line must report `OK`.

The official SDK result must be:

```text
b37661c5b1cd6c6e7751443ea0aa2bf4b410e4f6f5e063ca7554b4083cab6c76
```

## 3. Enter the wrapper directory

```bash
cd "$HOME/work/CP2105-Linux-Programming-Wrapper"
```

Git preserves the executable bits on all three supplied shell scripts.

## 4. Prepare Debian or Ubuntu

```bash
sudo ./prepare-linux-host.sh install
```

This installs required packages and stops/runtime-masks ModemManager for the
current boot. It does not open a CP2105.

## 5. Install the audited manufacturer executable

```bash
./install-official-cp210xsmt.sh \
    "$HOME/Downloads/USBXpressHostSDK-6.7.7-Linux.tar.gz"
```

The executable must report:

```text
d9f002fb1b890e294fc23ac4e7ce4fc2965fc7f2411ca315fcbf68a69fc6d745
```

## 6. Check the prepared host

```bash
./prepare-linux-host.sh check
```

Every line must report `PASS`.

## 7. Attach exactly one CP2105

Pass it through to the VM if applicable. Close terminals or serial monitors on
both tty interfaces.

```bash
sudo ./cp2105-smt-control.sh inspect
sudo ./cp2105-smt-control.sh list
```

Review the detected serial. The sysfs and manufacturer serial identities must
match.

## 8A. New virgin device

First run the read-only virgin check:

```bash
sudo ./cp2105-smt-control.sh preflight
```

Only after reviewing a successful virgin result and confirming the required
board state may an authorized operator run. Before authorization, verify that:

- the board's CP2105 electrical and programming requirements are satisfied;
- all five GPIO loads are safe for the fixed target profile; and
- all USB, board, external and possible back-power sources can be removed for
  the mandatory cold verification cycle.

Then run:

```bash
sudo ./cp2105-smt-control.sh program
```

After the manufacturer process ends, fully remove all USB and board power,
allow the rails to discharge, reconnect the same physical device, and run:

```bash
sudo ./cp2105-smt-control.sh verify-programmed
```

Do not run `program` again for that serial.

## 8B. Already-programmed or earlier-version device

Do not run `program`. Use the unconditional read-only target verification:

```bash
sudo ./cp2105-smt-control.sh verify-target
```

## Processing the next new device

Disconnect the completed device before attaching the next one. The wrapper
will detect the new serial and use a separate state directory automatically.

## After any reboot

```bash
sudo systemctl stop ModemManager.service
sudo systemctl mask --runtime ModemManager.service
```
