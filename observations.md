    ## Observations — Combined Stress Test (CPU + Memory + Disk)

### What I observed

Under combined CPU, memory, and disk stress, the system stayed responsive.
The OOM killer never fired — `dmesg` only shows the toggling of the OOM
killer around suspend/resume cycles and the `systemd-oomd` socket, but no
"Killed process" events. The 200 MB allocation was well within the 11 GB
of available RAM, so no process needed to be killed.

Specific observations from the run:

- **CPU:** Two `stress-ng-cpu` workers pegged at ~99% each in `top`,
  while every other process dropped to single-digit CPU usage. Load
  average climbed from 0.12 to ~1.99 over the 30-second run.
- **Memory:** `free -h` showed `used` rise by roughly the expected
  ~200 MB during the memory stress, then return to baseline after.
  Swap stayed near-idle (319 MB used out of 8 GB), so no page
  thrashing occurred.
- **Disk:** The tmpfs filled from 0% to 100% in about 25 iterations of
  the `dd` loop. Writes 26–30 failed cleanly with
  `No space left on device`. No kernel panic, no crash — just a clean
  `ENOSPC` refusal from the filesystem, which is exactly what the
  `size=256M` cap is meant to produce.
- **OOM:** `sudo dmesg | grep -i oom` returned only:
  - the boot-time `systemd-oomd.socket` message, and
  - five `OOM killer disabled` / `OOM killer enabled` pairs, which
    correspond to suspend/resume cycles, not actual kills.

### Why it stayed responsive

Three reasons the system never degraded:

1. **Ample resources.** 11 GB RAM, 8 GB swap, and a multi-core CPU meant
   the stress amounts (2 CPU workers, 200 MB memory, 256 MB tmpfs) were
   a small fraction of total capacity. Load average peaked at ~2, well
   under the number of available cores.
2. **Fair CPU scheduling.** The Linux CFS scheduler shares CPU time
   across all runnable processes, so the desktop, terminal, and `top`
   itself continued to get scheduled between the stress workers.
3. **Disk stress was RAM-backed.** The `dd` writes went to a `tmpfs`
   mount, which lives entirely in memory. The real disk, the root
   filesystem, and swap were untouched — no I/O wait, no slow flushes,
   no risk of filling `/var` or `/home`.

### What would be different in production

If this had been a real production server, the outcome would depend
heavily on headroom:

- **Less RAM or no swap:** A 1–2 GB VM running the same combined test
  would likely see the kernel OOM killer fire and kill a process,
  possibly the shell or a service. `dmesg` would show
  `Out of memory: Killed process <pid>`.
- **CPU-pinned workloads:** On a 1–2 core VM, two CPU-bound workers
  would starve everything else and the system would feel frozen.
- **Real disk instead of tmpfs:** Filling a real filesystem can break
  logging, crash services that can't write state, and cause cascading
  failures across the system.
- **Memory leak in the service:** Even with plenty of RAM, a slow leak
  would eventually push the system into swap, then into OOM territory.
  This is the classic 3 AM incident.

### Takeaway

The tmpfs `size=` cap is what turned a potentially catastrophic
"fill the disk until RAM is exhausted" scenario into a clean, contained
`ENOSPC` failure. Without that cap, the same `dd` loop would have kept
writing into RAM until the kernel had no choice but to start killing
processes. This is why `tmpfs` mounts should always be size-capped in
production — not just to protect the service, but to protect the
entire host from a single misbehaving workload.
