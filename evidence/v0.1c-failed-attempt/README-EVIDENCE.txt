CP2105 v0.1c FAILED-ATTEMPT EVIDENCE
====================================

This directory preserves the complete logs and consumed marker copied from:

  CP2105-cp210xsmt-wrapper-v0.1c-after-J6-correction.tar.gz

Source archive SHA-256:

  4F14FED62DA437F5CC47D9BD3E4FB96233D857EB29F587697E79E95462EFF6F5

Key evidence
------------

state/OTP_ATTEMPT_CONSUMED_DO_NOT_RETRY
  Original v0.1c marker created before the manufacturer programming boundary.

logs/20260829T114759Z-program.log
  Original v0.1c programming log. The official Silicon Labs command entered
  --set-and-verify-config, later terminated, and returned exit code 143.

logs/20260829T132919Z-inspect.log
logs/20260829T132919Z-preflight.log
  Read-only checks performed after removal of the J6 pins 9-10 shorting block.
  The exact CP2105 virgin configuration was still verified.

The v0.1c evidence is historical and must not be edited, deleted, or mistaken
for v0.1d's separate active one-shot state. v0.1d creates its own versioned
marker under the package's top-level state directory.

