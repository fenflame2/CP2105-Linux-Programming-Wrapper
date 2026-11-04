# Release Notes — v0.2b

## Board-neutral authorization release

v0.2b removes the Silicon Labs development-board J4/J6 confirmations from the
runtime programming and verification workflow. Those designators describe the
historical reference hardware preserved under `evidence/`; they are not valid
requirements for a different CP2105 board.

### Authorization changes

The two removed typed confirmations are:

- `J6 9-10 IS OPEN AND VERIFIED`
- `J4 1-2 AND 3-4 ARE INSTALLED`

The irreversible Program phase still requires four exact confirmations:

1. detected physical serial number;
2. fixed target-envelope SHA-256;
3. `PROGRAM CP2105 PERMANENTLY`; and
4. `I ACCEPT ONE IRREVERSIBLE ATTEMPT`.

The separate Verify phase still requires both exact confirmations that all
CP2105 power was removed and that the same device was reconnected.

### Board responsibility

The wrapper cannot inspect custom-board wiring. Before `program`, the operator
must verify the board's CP2105 electrical and programming requirements, ensure
all five GPIO loads are safe for the fixed target profile, and identify every
power or back-power path that must be removed for cold verification.

### Preserved safety behavior

- Exact virgin preflight before programming.
- Fixed, hash-locked five-GPIO target; no selectable profile.
- Runtime serial detection and manufacturer-list cross-check.
- Per-serial immutable one-attempt state.
- One `--set-config` transaction only.
- No `--set-and-verify-config` use and no automatic retry.
- Mandatory full power removal before separate read-only verification.
- No lock operation.
- Existing v0.2a consumed markers remain recognized and continue to block a
  repeat attempt for their serial.

No Silicon Labs executable or configuration payload was changed in v0.2b.
