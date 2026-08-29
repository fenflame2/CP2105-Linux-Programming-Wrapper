CP2105 v0.1d HARDWARE-PROVEN PROGRAMMING EVIDENCE
=================================================

Device
------
Part:          CP2105
Serial:        01E83F39
USB VID:PID:   10c4:ea70

Programming artifact
--------------------
Archive:       CP2105-cp210xsmt-wrapper-v0.1d.tar.gz
SHA-256:       71254C6C1EB492C049ED568A2D3584EECEBE1D1B3A656770B1291CC0EB024629

Result
------
At 2026-08-29T13:50:40Z, v0.1d invoked the audited Silicon Labs command:

  cp210xsmt --device-count 1 --set-and-verify-config CP2105-five-gpio-target.cfg

The manufacturer tool printed "Programmed 1 devices: OK". It then performed
five read-only verification attempts. Each immediate same-powered-session
read returned the new DeviceMode 01/01 but the original power-on-latched
DualPortConfig values 5151/FEFE/FEFE/10/10/10, so the tool exited 255 with
"Failed DualPortConfig verification".

No programming setter was retried. The v0.1d one-shot marker remained in place.

After complete USB power removal and reconnection, independent Windows
Manufacturing-DLL readback returned the exact target:

  DeviceMode            01 01
  Mode                  5D5F
  Reset_Latch           FEF0
  Suspend_Latch         FEF0
  EnhancedFxn           10 10 10
  Lock                  00

This proves the OTP programming transaction succeeded and the v0.1d failure
was a false-negative same-session verification result. The CP2105 must never
be programmed again.

Preserved files
---------------
logs/20260829T134923Z-program.log
  Exact v0.1d program log supplied from the programming host.

logs/20260829T135623Z-exact-readback-gdb.log
  Exact immediate post-attempt GDB field readback supplied from the host.

state/OTP_ATTEMPT_V01D_CONSUMED_DO_NOT_RETRY
  Exact immutable one-shot marker from the programming host.

POST-POWER-CYCLE-WINDOWS-READBACK.txt
  Text transcription and interpretation of the independent Windows readback.

post-power-cycle-windows-readback.png
  Original Windows application screenshot showing the final configuration.

