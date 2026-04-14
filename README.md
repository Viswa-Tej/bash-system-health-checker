# Bash System Health Checker

A production-grade Linux system health monitoring script that checks CPU, memory, disk, load average, top processes, and network connectivity — with colour-coded output, threshold-based alerting, Slack notifications, and automatic cron scheduling.

---

## What it does

- Checks **CPU usage** (reads /proc/stat directly — no `top` dependency)
- Checks **Memory usage** (reads /proc/meminfo)
- Checks **Disk usage** (root filesystem via `df`)
- Shows **Load averages** (1/5/15 minute from /proc/loadavg)
- Lists **Top 5 processes** by CPU consumption
- Tests **network connectivity** to 8.8.8.8, 1.1.1.1, google.com
- Displays **colour-coded ASCII progress bars** for each metric
- **Logs every run** to /var/log/health_check.log with timestamps
- **Sends Slack alerts** when thresholds are breached
- Installs as a **cron job** (runs every 5 minutes)

---

## Architecture

```
health_check.sh
├── get_cpu_usage()       reads /proc/stat twice, 1s apart → real CPU %
├── get_memory_usage()    reads /proc/meminfo → used/total/percent
├── get_disk_usage()      df -h / → usage percent + sizes
├── get_load_average()    /proc/loadavg → 1/5/15 min averages
├── get_top_processes()   ps aux --sort=-%cpu → top 5
├── check_network()       ping 3 targets → reachable/unreachable
├── bar()                 ASCII progress bar renderer
├── status_colour()       GREEN/YELLOW/RED based on thresholds
└── send_slack()          curl POST to Slack webhook if configured
```

---

## Thresholds (configurable at top of script)

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU    | > 70%   | > 90%    |
| Memory | > 75%   | > 90%    |
| Disk   | > 80%   | > 95%    |

---

## Quick start

```bash
# Clone and run immediately
git clone https://github.com/YOUR_USERNAME/bash-system-health-checker
cd bash-system-health-checker
chmod +x health_check.sh
bash health_check.sh
```

## Install as cron job (runs every 5 minutes)

```bash
sudo bash install.sh
```

## Enable Slack alerts

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
bash health_check.sh
```

To make Slack alerts permanent, add the export line to `/etc/environment`.

---

## Sample output

```
╔══════════════════════════════════════════════════════╗
║          SYSTEM HEALTH REPORT                        ║
║          myserver  —  2025-04-14 10:32:01            ║
╚══════════════════════════════════════════════════════╝

[ CPU ]
  Cores   : 4
  Usage   : [########----------------------] 28%  →  OK

[ MEMORY ]
  Total   : 7823 MB
  Used    : 3241 MB
  Usage   : [###############---------------] 50%  →  OK

[ DISK (/) ]
  Total   : 50G
  Used    : 18G  |  Available: 30G
  Usage   : [##############----------------] 46%  →  OK

[ LOAD AVERAGE ]
  1 min   : 0.42    5 min: 0.38    15 min: 0.31

[ TOP 5 PROCESSES BY CPU ]
  USER       %CPU   %MEM  COMMAND
  viswa      12.3   2.1   python3
  viswa       4.2   0.8   bash
  root        1.1   0.3   systemd

[ NETWORK CONNECTIVITY ]
  8.8.8.8:   reachable
  1.1.1.1:   reachable
  google.com: reachable

[ UPTIME ]
  up 3 days, 4 hours, 12 minutes

[ SUMMARY ]
  All systems healthy. No thresholds breached.
```

---

## Skills demonstrated

| Skill | How |
|-------|-----|
| Bash scripting | Functions, conditionals, arithmetic, string ops |
| Linux internals | Reading /proc/stat, /proc/meminfo, /proc/loadavg directly |
| SRE thinking | Thresholds, alerting, log rotation, cron scheduling |
| DevOps automation | Install script, idempotent cron setup |
| Observability | Metrics collection, colour-coded status, Slack integration |

---

## Tech stack
`Bash` · `Linux /proc filesystem` · `cron` · `Slack webhooks` · `curl`
