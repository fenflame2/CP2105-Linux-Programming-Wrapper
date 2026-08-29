# Release Notes — v0.2a

## Serial-agnostic multi-device release

v0.2a removes the fixed reference-device serial from the execution path. It
detects and binds any attached CP2105 serial at runtime while keeping the exact
target profile fixed and hash-locked.

### Device identity

- Requires exactly one attached `10c4:ea70` device.
- Reads a non-empty serial from sysfs.
- Cross-checks that exact serial against the manufacturer `--list` result.
- Requires the operator to re-enter the detected serial before programming.
- Rediscovers and rebinds the same serial after the mandatory power cycle.

### Per-device state

- Stores state beneath `state/devices/<SHA-256-of-exact-serial>/`.
- Keeps exact serial text inside each marker and log.
- Blocks repeat programming only for the consumed serial.
- Allows a different new serial to be processed independently in the same
  wrapper installation.
- Prevents a different attached device from satisfying another device's
  post-power-cycle verification phase.

### Portable installation

- Includes a direct public GitHub clone workflow for a fresh Linux host.
- Includes Debian/Ubuntu x86_64 prerequisite installation and checking.
- Accepts the official Silicon Labs SDK archive directly.
- Verifies both official SDK archive and executable SHA-256 identities.
- Does not redistribute Silicon Labs files.

### Preserved safety behavior

- Exact virgin preflight before programming.
- Fixed five-GPIO target envelope.
- One `--set-config` transaction only.
- No `--set-and-verify-config` use.
- No automatic programming retry.
- Mandatory complete power removal before separate read-only verification.
- No lock operation.

### Historical evidence

The reference-device serial appearing beneath `evidence/` is preserved audit
history only. It is not an expected serial or runtime constraint in v0.2a.
