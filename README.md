# Linux Load Test — bgdsvc_shanjid502

[![Platform](https://img.shields.io/badge/Platform-Fedora%2044-blue?logo=fedora)](https://getfedora.org/)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Security](https://img.shields.io/badge/SELinux-Enforcing-success)](https://github.com/SELinuxProject)
[![SSH](https://img.shields.io/badge/SSH%20Port-2222%20Hardened-orange?logo=openssh)](https://www.openssh.com/)
[![CI](https://img.shields.io/badge/Lint-ShellCheck-informational?logo=githubactions)](.github/workflows/lint.yml)

BongoDev Linux Fundamentals / DevOps Practical Lab  
Linux Deep Dive · DevOps Practical Lab

A production-grade test environment for a new internal service: dedicated service account, fast in-memory scratch storage (tmpfs), simulated workload stress testing, hardened SSH key-based access, automated cron monitoring, daily log rotation, and clean reverse-order teardown. Built and verified on **Fedora 44**.

---

<a id="table-of-contents"></a>

## 📑 Table of Contents

- [📐 Architecture & Lifecycle](#architecture--lifecycle)
- [👤 Service Account](#service-account)
- [📦 Prerequisites](#prerequisites)
- [📂 Repository Layout](#repository-layout)
- [🚀 Step-by-Step Execution Guide](#how-to-run)
  - [1. Service Account Creation](#1-create-the-service-account)
  - [2. In-Memory Scratch Space (tmpfs with Size Cap)](#2-mount-the-tmpfs-scratch-space)
  - [3. Workload Stress Testing (CPU, Memory, Disk, All)](#3-stress-test)
  - [4. SSH Key-Based Authentication](#4-ssh-access)
  - [5. SSH Hardening (Port 2222, Root & Password Auth Disabled)](#5-ssh-hardening)
  - [6. Automated Cron Monitoring & Nightly Cleanup](#6-cron-monitoring)
  - [7. Logrotate Configuration & Verification](#7-logrotate)
  - [8. Clean Reverse Teardown (Idempotent Teardown)](#8-cleanup)
- [🐧 Fedora, SELinux & Firewalld Implementation Notes](#fedora-specific-notes)
- [🧠 Deep Dive: Key Observations & Incident Analysis](#key-observations)
- [📸 Screenshots & Verification Gallery](#screenshots--verification-gallery)
- [🔐 Security & Credential Protection](#security)
- [✍️ Author](#author)

---

## Architecture & Lifecycle

```mermaid
flowchart TD
    subgraph Build ["1. Provisioning & Setup"]
        A["01_create_user.sh<br/>Identity: bgdsvc_shanjid502 (nologin)"] --> B["02_setup_tmpfs.sh<br/>RAM Scratch: /mnt/..._tmp (capped at 256M)"]
        B --> C["03_stress_and_populate.sh<br/>CPU (2 cores), RAM (200M), Disk (30x10M)"]
        C --> D["SSH Hardening<br/>Port 2222, Keys only, AllowUsers"]
        D --> E["Monitoring & Logrotate<br/>5-min Cron Health Check + Daily Rotate"]
    end

    subgraph Teardown ["2. Reverse Teardown (04_cleanup.sh)"]
        F["1. Kill running processes (pkill -u)"] --> G["2. Remove cron automation & rotate rules"]
        G --> H["3. Unmount tmpfs & remove mountpoint"]
        H --> I["4. Remove log directories (/var/log/...)"]
        I --> J["5. Delete user identity (userdel -r)"]
    end

    Build -.->|"Test Completed"| Teardown
```

---

## Service account

```
bgdsvc_shanjid502
```

A system account (UID 958) with shell `/usr/sbin/nologin` at creation
time. Ownership of all test resources belongs to this account.

---

## Prerequisites

- Fedora (tested on Fedora 44) with `sudo`
- Packages: `openssh-server`, `stress-ng`, `policycoreutils-python-utils`, `cronie`
- SELinux enforcing (Fedora default)
- firewalld active (Fedora default)

Install missing packages:

```bash
sudo dnf install -y openssh-server stress-ng policycoreutils-python-utils cronie
```

---

## Repository layout

```
linux-load-testing/
├── .github/
│   └── workflows/
│       └── lint.yml
├── .gitignore
├── README.md
├── observations.md
├── scripts/
│   ├── 01_create_user.sh
│   ├── 02_setup_tmpfs.sh
│   ├── 03_stress_and_populate.sh
│   ├── 04_cleanup.sh
│   ├── bgdsvc_shanjid502_monitor.sh
│   └── bgdsvc_shanjid502_cleanup_old_files.sh
└── screenshots/
    ├── 00_svc_name.png
    ├── 01_id_created.png
    ├── 02_df_before.png
    ├── 02_df_fill.png
    ├── 02_df_after.png
    ├── 03_free_before.png
    ├── 03_free_during.png
    ├── 03_free_after.png
    ├── 03_dmesg_oom.png
    ├── 04_ssh_key_success.png
    ├── 04_ssh_success.png
    ├── 05_crontab_l.png
    ├── 06_cleanup_verify.png
    └── 07_logrotate.png
```

---

## How to run

All scripts accept the service name as an argument and are safe to
run multiple times (idempotent). Run them with `sudo` from the repo
root.

### 1. Create the service account

```bash
sudo ./scripts/01_create_user.sh bgdsvc_shanjid502
```

Creates a system account with `useradd -r -m -s /usr/sbin/nologin`.
Skips creation if the account already exists. Prints `id` and
`getent passwd` output to confirm.

### 2. Mount the tmpfs scratch space

```bash
sudo ./scripts/02_setup_tmpfs.sh bgdsvc_shanjid502
```

Mounts a 256M tmpfs at `/mnt/bgdsvc_shanjid502_tmp`, owned by the
service account. The `size=256M` cap is mandatory — without it, tmpfs
can grow until it consumes all RAM.

The script checks `mountpoint -q` before mounting, so re-runs skip the
mount step cleanly.

### 3. Stress test

```bash
# One mode at a time
sudo ./scripts/03_stress_and_populate.sh bgdsvc_shanjid502 --cpu
sudo ./scripts/03_stress_and_populate.sh bgdsvc_shanjid502 --mem
sudo ./scripts/03_stress_and_populate.sh bgdsvc_shanjid502 --disk

# All three in parallel
sudo ./scripts/03_stress_and_populate.sh bgdsvc_shanjid502 --all
```

- `--cpu` — 2 CPU workers via `stress-ng --cpu 2 --timeout 30s`
- `--mem` — 1 VM worker via `stress-ng --vm 1 --vm-bytes 200M --timeout 30s`
- `--disk` — writes 30 × 10M files into the tmpfs (`seq 1 30`)
- `--all` — runs all three in parallel

All `stress-ng` invocations use `--temp-path /tmp` so the service
account can write scratch files.

**Note on `seq 1 30`:** The handout suggests 20 files, but 20 × 10M =
200M, which does not hit the 256M cap. Using 30 guarantees the tmpfs
fills and `dd` fails with `No space left on device`.

### 4. SSH access

Key-based SSH to the service account on port 2222.

```bash
# Generate a key pair (once)
ssh-keygen -t ed25519 -f ~/.ssh/bgdsvc_shanjid502_key

# Install the public key on the service account
sudo mkdir -p /home/bgdsvc_shanjid502/.ssh
sudo cp ~/.ssh/bgdsvc_shanjid502_key.pub \
        /home/bgdsvc_shanjid502/.ssh/authorized_keys
sudo chown -R bgdsvc_shanjid502:bgdsvc_shanjid502 \
        /home/bgdsvc_shanjid502/.ssh
sudo chmod 700 /home/bgdsvc_shanjid502/.ssh
sudo chmod 600 /home/bgdsvc_shanjid502/.ssh/authorized_keys

# Fedora: fix SELinux context so sshd can read the key
sudo restorecon -Rv /home/bgdsvc_shanjid502/.ssh

# Allow interactive login (lab only — production would keep nologin)
sudo usermod -s /bin/bash bgdsvc_shanjid502

# Connect
ssh -i ~/.ssh/bgdsvc_shanjid502_key -p 2222 bgdsvc_shanjid502@localhost
```

### 5. SSH hardening

Edit `/etc/ssh/sshd_config` and set:

```conf
Port 2222
PermitRootLogin no
PasswordAuthentication no
AllowUsers bgdsvc_shanjid502
```

**Fedora-specific: SELinux + firewalld must be told about port 2222
before sshd will bind to it.**

```bash
# Tell SELinux that sshd may listen on 2222
sudo semanage port -a -t ssh_port_t -p tcp 2222

# Open 2222 in firewalld
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --reload

# Validate config before restart
sudo sshd -t

# Restart sshd
sudo systemctl restart sshd

# Confirm the new port
sudo systemctl status sshd
sudo ss -tlnp | grep sshd
```

Verification:

```bash
# Allowed account — succeeds
ssh -i ~/.ssh/bgdsvc_shanjid502_key -p 2222 bgdsvc_shanjid502@localhost

# Other users — refused (AllowUsers)
ssh -p 2222 levi9111@localhost
ssh -p 2222 root@localhost

# Password auth — refused
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -p 2222 bgdsvc_shanjid502@localhost
```

### 6. Cron monitoring

Two scripts are scheduled via the service account's crontab:

- `/usr/local/bin/bgdsvc_shanjid502_monitor.sh` — logs `free -h`,
  `df -h` on the tmpfs, and `ps -u` every 5 minutes.
- `/usr/local/bin/bgdsvc_shanjid502_cleanup_old_files.sh` — deletes
  tmpfs files older than 1 day, every night at 02:00.

Log directory:

```bash
sudo mkdir -p /var/log/bgdsvc_shanjid502
sudo chown bgdsvc_shanjid502:bgdsvc_shanjid502 /var/log/bgdsvc_shanjid502
sudo restorecon -Rv /var/log/bgdsvc_shanjid502
```

Install the crontab:

```bash
sudo crontab -u bgdsvc_shanjid502 -e
```

Contents:

```cron
*/5 * * * * /usr/local/bin/bgdsvc_shanjid502_monitor.sh
0 2 * * * /usr/local/bin/bgdsvc_shanjid502_cleanup_old_files.sh
```

Verify:

```bash
sudo crontab -l -u bgdsvc_shanjid502
sudo systemctl status crond
```

**Reminder:** cron entries and script contents are not shell scripts.
`$SVC_NAME` will not expand there — the literal name is used instead.

### 7. Logrotate

Create `/etc/logrotate.d/bgdsvc_shanjid502`:

```conf
/var/log/bgdsvc_shanjid502/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
    create 0640 bgdsvc_shanjid502 bgdsvc_shanjid502
}
```

Test:

```bash
sudo logrotate -d /etc/logrotate.d/bgdsvc_shanjid502   # dry run
sudo logrotate -f /etc/logrotate.d/bgdsvc_shanjid502   # force
ls -lh /var/log/bgdsvc_shanjid502/
```

You should see the current log plus a compressed `.gz` of the previous
one, owned by the service account with `0640` permissions.

### 8. Cleanup

```bash
sudo ./scripts/04_cleanup.sh bgdsvc_shanjid502
```

Reverse-order teardown:

1. Kill processes owned by the service account
2. Remove crontab, logrotate rule, and both scripts
3. Unmount and remove the tmpfs
4. Remove the log directory
5. Remove the service account with `userdel -r`

Idempotent — safe to run twice, safe to run if any step already failed.

Verify clean state:

```bash
id bgdsvc_shanjid502        # should fail
mount | grep bgdsvc         # should be empty
ps -u bgdsvc_shanjid502     # should be empty
```

[▲ Back to Top](#table-of-contents)

---

## Fedora-specific notes

| Topic                       | Note                                                                |
| --------------------------- | ------------------------------------------------------------------- |
| SSH service name            | `sshd`, not `ssh`                                                   |
| Package manager             | `dnf`, not `apt`                                                    |
| Firewall                    | `firewalld`, not `ufw`                                              |
| SELinux                     | Enforcing by default                                                |
| SELinux + custom port       | `semanage port -a -t ssh_port_t -p tcp 2222` before restarting sshd |
| SELinux + `authorized_keys` | `restorecon -Rv ~/.ssh` after copying keys, else sshd ignores them  |
| SELinux + `/var/log` subdir | `restorecon -Rv /var/log/bgdsvc_shanjid502` after `mkdir`           |
| Cron daemon                 | `crond`, managed by systemd                                         |

[▲ Back to Top](#table-of-contents)

---

## Key observations

See `observations.md` for the full write-up. Summary:

- Under combined CPU + memory + disk stress the system stayed
  responsive. The kernel OOM killer never fired — `dmesg` showed only
  the `systemd-oomd` socket and suspend/resume toggles, no actual
  kill events.
- The reason was headroom: 11 GB RAM, 8 GB swap, and multi-core CPU
  absorbed the stress easily. `stress-ng` reported ~543 MB available
  during `--all`, down from ~722 MB during `--mem` alone — the
  difference was the tmpfs fill consuming RAM.
- The disk fill hit the 256 MB tmpfs cap cleanly at file 26 with
  `No space left on device`. No kernel panic, no crash. The size cap
  is what turned a potentially catastrophic scenario into a contained
  failure.
- In production, I would expect different results on a smaller VM with
  no swap — the OOM killer would likely fire, and `dmesg` would show
  `Out of memory: Killed process`. I would use cgroups to cap the
  service, alert on memory and disk thresholds, and test against a
  staging host that mirrors production resources.

[▲ Back to Top](#table-of-contents)

---

## Screenshots & Verification Gallery

Every step of the lab has been executed, observed, and recorded. Expand each section below to inspect the evidence.

<details open>
<summary><b>1. Service Identity & Storage Setup</b></summary>

|        Service Name Confirmation         |        Service Account Created (`id`)        |
| :--------------------------------------: | :------------------------------------------: |
| ![SVC Name](screenshots/00_svc_name.png) | ![ID Created](screenshots/01_id_created.png) |

|   tmpfs Before Fill (Empty / 256M Free)    | tmpfs After Fill (100% Cap Clean Failure) |
| :----------------------------------------: | :---------------------------------------: |
| ![df before](screenshots/02_df_before.png) | ![df after](screenshots/02_df_after.png)  |

</details>

<details>
<summary><b>2. System Under Stress & OOM Verification</b></summary>

|              Memory Before Stress              |         Memory During Combined Stress          |       Memory After Stress (Recovered)        |
| :--------------------------------------------: | :--------------------------------------------: | :------------------------------------------: |
| ![free before](screenshots/03_free_before.png) | ![free during](screenshots/03_free_during.png) | ![free after](screenshots/03_free_after.png) |

|   OOM Killer Check (`dmesg` - No Kills)    |        Filling tmpfs in Action         |
| :----------------------------------------: | :------------------------------------: |
| ![dmesg oom](screenshots/03_dmesg_oom.png) | ![df fill](screenshots/02_df_fill.png) |

</details>

<details>
<summary><b>3. SSH Hardening, Automation & Reverse Teardown</b></summary>

|           Key-Based SSH on Port 2222           |      Cron Jobs Active (`crontab -l`)       |
| :--------------------------------------------: | :----------------------------------------: |
| ![ssh success](screenshots/04_ssh_success.png) | ![crontab l](screenshots/05_crontab_l.png) |

|     Logrotate Execution & Compression      |             Clean Teardown Verification              |
| :----------------------------------------: | :--------------------------------------------------: |
| ![logrotate](screenshots/07_logrotate.png) | ![cleanup verify](screenshots/06_cleanup_verify.png) |

</details>

[▲ Back to Top](#table-of-contents)

---

## Security

The private SSH key (`~/.ssh/bgdsvc_shanjid502_key`) is **not**
committed to this repository. Only the `.pub` file is safe to share.

`.gitignore` includes:

```
*_key
!*.pub
```

[▲ Back to Top](#table-of-contents)

---

## Author

- Name: Shanjid Ahmad
- Service account: `bgdsvc_shanjid502`
- Host: Fedora Workstation 44 (localhost)
