# 10 — robothost stability: hunting the random hard-hang

> Milestone M10 (in progress). robothost (the libvirt hypervisor hosting the node01
> guest) **hard-hangs at random** — frozen, no video signal, kernel log just stops.
> M9 moved the control-plane off it onto sowilo; this milestone is about making
> robothost itself reliable so node01 can be un-cordoned and trusted again.

## Symptom

- Total **hard lockup**: machine freezes solid, attaching a monitor shows **no
  signal**, the kernel log ends mid-stream with **no panic / oops / ext4 / thermal /
  OOM**. On power-cycle it boots fine.
- **Random time-to-hang: 20–30 min to days/weeks**, day or night, **including while
  idle on a bare GNOME desktop** (low load).
- Visible in `journalctl --list-boots` as gaps where a boot's journal ends but the
  next boot is much later (machine was dead until a manual reset) — e.g. 2026-06-29
  a boot died ~07:28 and stayed dead until a manual reset at 09:38 (~2 h).

## Ruled out

- **Disk failure — NO.** SMART on the NVMe (Vi3000 2TB) is healthy: `Percentage Used
  0%`, `Available Spare 100%` (no reallocations), 30 °C, internal error log empty.
  The `critical medium error` bursts (≈1579 in a day) + `Media/Data Integrity Errors
  139` are **corruption caused by the hangs**: each manual hard-reset is an unsafe
  shutdown (69 logged) that interrupts in-flight writes → those LBAs read back as
  medium errors → corrupt container-image layers (`exec format error`). The disk is a
  victim, not the cause. Repairable by rewriting affected LBAs once hangs stop.
- **Spontaneous power loss — NO.** The "unsafe shutdowns" are all manual resets after
  a hang, not the machine losing power on its own.
- **CPU chiplet / uneven die cooling — N/A.** The CPU is an **Intel i3-8109U**
  (Coffee Lake-U), a single monolithic die — no chiplets.
- **Thermal as primary cause — unlikely.** It hangs while idle (idle ≠ hot); the
  `cpu-fan-control.service` fix keeps `x86_pkg_temp` ~60 °C; and a real thermal event
  triggers THERMTRIP (instant power-off), not a frozen-but-powered hang. Keep temp
  monitoring as insurance, not as the lead.

## Hardware facts

- **Intel NUC8i3BEK** (Bean Canyon): i3-8109U (2c/4t), **Iris Plus Graphics 655**
  (GT3e, i915), 15 GiB-class RAM. Single NVMe (OS + node01 VM image).
- **BIOS `BECFL357.86A.0041`, dated 2018-07-19** — very old.
- Dual link: wired **`eno1` 192.168.0.25** + WiFi **`wlp0s20f3` 192.168.0.162** (DNS /
  ssh currently use the WiFi IP).
- `node-exporter` runs on `:9100` and is scraped **off-box** by sowilo's vmagent, so
  temperature history survives a hang.

## Leading hypotheses

1. **Old BIOS.** NUC8 / Bean Canyon had documented random-hang bugs fixed in later
   BIOS releases; `0041` (2018) is far behind current (~`0086`+). Cheapest likely fix.
2. **i915 / display stack.** Before crashes the log showed escalating
   `i915_hpd_poll_init_work hogged CPU` (16→32→64→128→256×). HPD polling runs at idle;
   "no video on attach" + idle freezes fit an Intel-GPU/display-PM hang (PSR/DC/RC6).
3. **RAM / board fault.** Random over minutes-to-weeks is also a classic intermittent
   hardware signature; test if 1 & 2 don't resolve it.

## Plan (by priority)

1. **[done, observing] Go headless.** Disabled `gdm`, default target set to
   `multi-user.target` — removes the GNOME compositor and most i915 activity (incl.
   HPD polling). The reboot that applied this was the **first clean shutdown of the
   day** and booted in ~28 s. **Now: run headless under load and watch whether the
   hangs stop.** If they stop → it was the GUI/i915 stack.
2. **[done] Update the BIOS.** `0041` (2018) → **`BECFL357.86A.0098`** (2026-02-04).
3. **[configured, pending one reboot] Hardware watchdog + auto-reboot on hang** —
   breaks the "hang → manual hard-reset → NVMe corruption" loop so the box
   self-recovers (critical for the multi-hour night-time hangs).
   **Gotcha:** this NUC8 publishes an **ACPI WDAT** table, so the kernel hands the
   watchdog to `wdat_wdt` and blocks `iTCO_wdt` — but `wdat_wdt` fails to probe
   (`ioremap failed ... error -12`, a known NUC WDAT bug), leaving **no
   `/dev/watchdog` at all**. Fix: boot param **`acpi_no_watchdog`** so the kernel
   ignores WDAT and `iTCO_wdt` claims the hardware. (`softdog` is useless here — a
   software timer can't reset a fully-frozen CPU; the hardware iTCO is the point.)
   Configured (all non-disruptive; **activates on the next reboot**):
   ```bash
   # GRUB: append acpi_no_watchdog to GRUB_CMDLINE_LINUX_DEFAULT, then:
   sudo update-grub
   echo iTCO_wdt | sudo tee /etc/modules-load.d/watchdog.conf
   # systemd pets /dev/watchdog; on a full freeze it stops → hardware resets:
   printf '[Manager]\nRuntimeWatchdogSec=60s\nRebootWatchdogSec=5min\n' \
     | sudo tee /etc/systemd/system.conf.d/10-watchdog.conf
   printf 'kernel.panic=10\nkernel.hardlockup_panic=1\nkernel.softlockup_panic=0\n' \
     | sudo tee /etc/sysctl.d/99-lockup.conf && sudo sysctl --system
   ```
   After the reboot verify: `ls /dev/watchdog`, `systemctl show -p RuntimeWatchdogUSec`
   (=1min), `cat /sys/class/watchdog/watchdog0/identity` (iTCO_wdt). robothost runs 4
   autostart VMs (incl. a W2022 DC) — the reboot drops all of them briefly; they
   recover (`autostart=enable`).
4. **netconsole → sowilo** to capture the last kernel words of the next hang (i915
   hangs often emit a GPU-hang/reset line right before freezing):
   ```bash
   # robothost (set iface + sowilo MAC):
   sudo modprobe netconsole netconsole=6665@192.168.0.162/<iface>,6666@192.168.0.92/<sowilo-MAC>
   # sowilo:  socat -u udp-recv:6666 - | tee ~/robothost-netconsole.log
   ```
5. **Prefer wired `eno1`** for SSH/monitoring (WiFi `iwlwifi` is another thing that can
   wedge the kernel; one fewer variable).

## Exit criteria

robothost runs headless **under load** for a sustained stretch without a hang; then
update BIOS + add the watchdog as belt-and-suspenders, re-enable node01 (un-cordon,
re-enable its Longhorn disk, drop the metallb `postRenderers` + the longhorn-csi-plugin
live patch from M9), and let Longhorn rebuild the 2nd replica.
