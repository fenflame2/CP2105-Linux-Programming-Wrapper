# CP2105 Linux Controlled Programming Wrapper v0.2a

This repository contains a Linux safety wrapper around the unchanged Silicon
Labs USBXpress Host SDK 6.7.7 `cp210xsmt` executable.

Version v0.2a is serial-agnostic. It can process any new CP2105 serial number,
one attached device at a time, while retaining an independent permanent
one-shot history for every device it encounters.

The target configuration remains deliberately fixed. The attached physical
device identity is discovered and bound at runtime.

## Runtime device-identity model

There is no compiled-in expected serial number. Before any manufacturer read or
write operation, the wrapper:

1. Requires exactly one USB `10c4:ea70` device.
2. Reads that device's non-empty serial from sysfs.
3. Requires exactly two tty interfaces belonging to that same USB device.
4. Runs the manufacturer's read-only `--list` operation.
5. Requires the manufacturer output to contain exactly one exact match for the
   sysfs serial.

Before irreversible programming, the operator must re-enter the detected
serial exactly. The consumed marker stores that serial and its state key.

Device state is held beneath:

```text
state/devices/<SHA-256-of-exact-serial>/
```

Using the serial hash for the directory makes state-path construction safe even
if a legitimate serial contains spaces or punctuation. The exact serial remains
visible inside every marker and log.

After the mandatory physical power cycle, `verify-programmed` rediscovers the
attached device and requires the consumed marker belonging to that exact
serial. Connecting a different CP2105 cannot complete the first device's
verification phase.

## Fixed target profile

- CP2105 USB VID:PID `10c4:ea70`
- target envelope `01 01 5F 5D F0 FE F0 FE 10 10 10 00`
- envelope SHA-256
  `A5CF6A6FCFD97D2B99E97FEAE88B68FCAACA9A6F14BDAD346E1C732E170F7722`
- no lock operation

This wrapper is serial-agnostic, but it is not profile-agnostic. Every
authorized new device receives the same hash-locked five-GPIO configuration.

## Two-phase programming architecture

Phase 1 runs the complete virgin preflight, creates the detected serial's
immutable consumed marker, requires six exact confirmations, and invokes one
manufacturer setter transaction:

```bash
sudo ./cp2105-smt-control.sh program
```

```text
cp210xsmt --device-count 1 --set-config CP2105-five-gpio-target.cfg
```

The wrapper never uses `--set-and-verify-config` and never retries a setter.

After the manufacturer process ends, the wrapper labels the target as not yet
verified. Remove all USB and board power, allow the rails to discharge,
reconnect the same physical CP2105 with J6 pins 9-10 open, and then run:

```bash
sudo ./cp2105-smt-control.sh verify-programmed
```

That second phase invokes only:

```text
cp210xsmt --device-count 1 --verify-config CP2105-five-gpio-target.cfg
```

A verification failure never authorizes another programming transaction. The
read-only phase may be repeated after correcting a connection, VM passthrough,
power-cycle, or process-interference problem.

## Reference-device evidence

The `evidence/` directory preserves the original hardware investigation that
proved why a true power cycle is required. Its historical files identify the
reference device used during development; that serial is evidence only and is
not an execution constraint in v0.2a.

The v0.1d manufacturer transaction reported `Programmed 1 devices: OK`, then
produced a false-negative same-powered-session `DualPortConfig` verification.
After complete power removal, the reference device read back the exact target:

```text
DeviceMode         01 01
Mode               5D5F
Reset_Latch        FEF0
Suspend_Latch      FEF0
EnhancedFxn        10 10 10
Lock               00
```

## Supported fresh host

The supplied host installer supports:

- Debian or Ubuntu
- x86_64 CPU
- systemd
- `apt-get`

The programming path was hardware-proven on Ubuntu 22.04. Follow
[`FRESH-LINUX-INSTALL.md`](FRESH-LINUX-INSTALL.md) for the clean-machine
procedure.

## Required Silicon Labs download

Download the Linux USBXpress Host SDK 6.7.7 from the official
[Silicon Labs CP2105 product page](https://www.silabs.com/interface/usb-bridges/classic/device.cp2105).

Required archive identity:

```text
Filename: USBXpressHostSDK-6.7.7-Linux.tar.gz
SHA-256:  b37661c5b1cd6c6e7751443ea0aa2bf4b410e4f6f5e063ca7554b4083cab6c76
```

Required installed executable identity:

```text
Filename: cp210xsmt
SHA-256:  d9f002fb1b890e294fc23ac4e7ce4fc2965fc7f2411ca315fcbf68a69fc6d745
```

The Silicon Labs SDK and executable are not redistributed. The installer
rejects every other archive and executable.

## Fresh-machine installation from GitHub

Install Git, clone this public repository, and enter the working directory:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates git

mkdir -p "$HOME/work"
git clone \
    https://github.com/fenflame2/CP2105-Linux-Programming-Wrapper.git \
    "$HOME/work/CP2105-Linux-Programming-Wrapper"

cd "$HOME/work/CP2105-Linux-Programming-Wrapper"
sha256sum --check SHA256SUMS
```

Then install the required host packages and the separately downloaded official
Silicon Labs SDK executable:

```bash
sudo ./prepare-linux-host.sh install

./install-official-cp210xsmt.sh \
    "$HOME/Downloads/USBXpressHostSDK-6.7.7-Linux.tar.gz"

./prepare-linux-host.sh check
```

No command above opens a CP2105 device.

## Read-only device inspection

Attach exactly one CP2105 and ensure neither tty interface is open:

```bash
sudo ./cp2105-smt-control.sh inspect
sudo ./cp2105-smt-control.sh list
```

For a new device, prove the exact virgin baseline before considering
programming:

```bash
sudo ./cp2105-smt-control.sh preflight
```

For an already-programmed device or recovery from an earlier wrapper version,
use the unconditional read-only target check:

```bash
sudo ./cp2105-smt-control.sh verify-target
```

## Processing multiple new devices

The same installed wrapper directory can process multiple devices sequentially:

1. Attach exactly one new CP2105.
2. Run `preflight` and review the detected serial and virgin result.
3. Run `program` only with explicit authorization.
4. Fully power-cycle that same device.
5. Run `verify-programmed` and preserve its success marker.
6. Disconnect it before attaching the next new CP2105.

A consumed marker blocks only its own serial. It does not authorize, consume,
or block a different serial.

## Required hardware and host state

- J6 pins 9-10 electrically open
- J4 pins 1-2 installed
- J4 pins 3-4 installed
- exactly one `10c4:ea70` device
- readable, non-empty USB serial
- both CP2105 tty interfaces closed
- ModemManager inactive
- no pre-existing `cp210xsmt` process

J1 pins 9-10 do not isolate VPP. The relevant configuration-ROM programming
connection is J6 pins 9-10.

## ModemManager after reboot

The supplied preparation script uses a runtime mask, which intentionally ends
at reboot. Before CP2105 access after any reboot, run:

```bash
sudo systemctl stop ModemManager.service
sudo systemctl mask --runtime ModemManager.service
```

If ModemManager is not installed, no action is needed.

## Repository and redistribution boundary

Do not commit or attach the Silicon Labs SDK archive or `vendor/cp210xsmt`.
The Git repository and any optional release archive contain only this wrapper.
Every operator obtains the official SDK from Silicon Labs and runs the supplied
hash-locked installer.

Runtime logs and `state/devices/` are local audit records and are excluded from
Git. Preserve the complete local wrapper directory after any irreversible
attempt. Never delete a consumed marker merely to retry a device.
