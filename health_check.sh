#!/usr/bin/env bash
# ============================================================
#  System Health Checker
#  Author  : Viswa Teja Payam
#  Role    : DevOps / SRE Engineer
#  Purpose : Checks CPU, Memory, Disk, Load Average, Top
#            processes and network connectivity. Outputs a
#            colour-coded report and sends a Slack alert when
#            any threshold is breached.
# ============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
CPU_WARN=70       # warn  if CPU  usage > 70%
CPU_CRIT=90       # alert if CPU  usage > 90%
MEM_WARN=75       # warn  if MEM  usage > 75%
MEM_CRIT=90       # alert if MEM  usage > 90%
DISK_WARN=80      # warn  if DISK usage > 80%
DISK_CRIT=95      # alert if DISK usage > 95%
LOG_FILE="/var/log/health_check.log"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"   # set via env variable

# ── Colours ───────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
log() {
    # writes to stdout AND to the log file with a timestamp
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

status_colour() {
    # $1 = value (integer), $2 = warn threshold, $3 = crit threshold
    if   (( $1 >= $3 )); then echo -e "${RED}CRITICAL${RESET}"
    elif (( $1 >= $2 )); then echo -e "${YELLOW}WARNING${RESET}"
    else                       echo -e "${GREEN}OK${RESET}"
    fi
}

bar() {
    # draws a simple ASCII progress bar
    # $1 = percentage (0-100), $2 = bar width (default 30)
    local pct=$1 width=${2:-30}
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    printf '['
    printf '%0.s#' $(seq 1 $filled)
    printf '%0.s-' $(seq 1 $empty)
    printf '] %d%%' "$pct"
}

send_slack() {
    # sends a message to Slack if SLACK_WEBHOOK is configured
    local message="$1"
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK" > /dev/null
    fi
}

# ── Collectors ────────────────────────────────────────────────
get_cpu_usage() {
    # reads /proc/stat twice 1 second apart to get real CPU usage
    # avoids calling `top` which behaves differently across distros
    local cpu1 cpu2 idle1 idle2 total1 total2
    read -r _ user1 nice1 sys1 idle1 iowait1 irq1 sirq1 _ < /proc/stat
    sleep 1
    read -r _ user2 nice2 sys2 idle2 iowait2 irq2 sirq2 _ < /proc/stat

    total1=$(( user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + sirq1 ))
    total2=$(( user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + sirq2 ))

    local delta_total=$(( total2 - total1 ))
    local delta_idle=$(( (idle2 + iowait2) - (idle1 + iowait1) ))
    local delta_used=$(( delta_total - delta_idle ))

    echo $(( delta_used * 100 / delta_total ))
}

get_memory_usage() {
    # parses /proc/meminfo — works on all Linux systems
    local mem_total mem_available
    mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    local mem_used=$(( mem_total - mem_available ))
    echo "$(( mem_used * 100 / mem_total )) $mem_total $mem_used"
}

get_disk_usage() {
    # returns usage percentage for the root filesystem
    df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5, $2, $3, $4}'
}

get_load_average() {
    # reads 1/5/15 minute load averages from /proc/loadavg
    awk '{print $1, $2, $3}' /proc/loadavg
}

get_top_processes() {
    # top 5 processes by CPU usage
    ps aux --sort=-%cpu | awk 'NR==1 || NR<=6 {printf "  %-10s %-6s %-6s %s\n", $1, $3, $4, $11}'
}

check_network() {
    # pings 3 targets — returns OK or FAIL for each
    local targets=("8.8.8.8" "1.1.1.1" "google.com")
    for t in "${targets[@]}"; do
        if ping -c 1 -W 2 "$t" &>/dev/null; then
            echo -e "  ${t}: ${GREEN}reachable${RESET}"
        else
            echo -e "  ${t}: ${RED}unreachable${RESET}"
        fi
    done
}

# ── Main Report ───────────────────────────────────────────────
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          SYSTEM HEALTH REPORT                        ║"
    echo "║          $(hostname)  —  $(date '+%Y-%m-%d %H:%M:%S')         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    local alerts=()

    # ── CPU ───────────────────────────────────────────────────
    echo -e "${BOLD}[ CPU ]${RESET}"
    local cpu_pct
    cpu_pct=$(get_cpu_usage)
    local cpu_cores
    cpu_cores=$(nproc)
    echo -e "  Cores   : ${cpu_cores}"
    echo -ne "  Usage   : "
    bar "$cpu_pct"
    echo -e "  →  $(status_colour "$cpu_pct" "$CPU_WARN" "$CPU_CRIT")"
    if (( cpu_pct >= CPU_CRIT )); then
        alerts+=("CRITICAL: CPU at ${cpu_pct}%")
    elif (( cpu_pct >= CPU_WARN )); then
        alerts+=("WARNING: CPU at ${cpu_pct}%")
    fi
    echo ""

    # ── Memory ────────────────────────────────────────────────
    echo -e "${BOLD}[ MEMORY ]${RESET}"
    read -r mem_pct mem_total_kb mem_used_kb <<< "$(get_memory_usage)"
    local mem_total_mb=$(( mem_total_kb / 1024 ))
    local mem_used_mb=$(( mem_used_kb / 1024 ))
    echo -e "  Total   : ${mem_total_mb} MB"
    echo -e "  Used    : ${mem_used_mb} MB"
    echo -ne "  Usage   : "
    bar "$mem_pct"
    echo -e "  →  $(status_colour "$mem_pct" "$MEM_WARN" "$MEM_CRIT")"
    if (( mem_pct >= MEM_CRIT )); then
        alerts+=("CRITICAL: Memory at ${mem_pct}%")
    elif (( mem_pct >= MEM_WARN )); then
        alerts+=("WARNING: Memory at ${mem_pct}%")
    fi
    echo ""

    # ── Disk ──────────────────────────────────────────────────
    echo -e "${BOLD}[ DISK (/) ]${RESET}"
    read -r disk_pct disk_total disk_used disk_avail <<< "$(get_disk_usage)"
    echo -e "  Total   : ${disk_total}"
    echo -e "  Used    : ${disk_used}  |  Available: ${disk_avail}"
    echo -ne "  Usage   : "
    bar "$disk_pct"
    echo -e "  →  $(status_colour "$disk_pct" "$DISK_WARN" "$DISK_CRIT")"
    if (( disk_pct >= DISK_CRIT )); then
        alerts+=("CRITICAL: Disk at ${disk_pct}%")
    elif (( disk_pct >= DISK_WARN )); then
        alerts+=("WARNING: Disk at ${disk_pct}%")
    fi
    echo ""

    # ── Load Average ──────────────────────────────────────────
    echo -e "${BOLD}[ LOAD AVERAGE ]${RESET}"
    read -r load1 load5 load15 <<< "$(get_load_average)"
    echo -e "  1 min   : ${load1}    5 min: ${load5}    15 min: ${load15}"
    echo ""

    # ── Top Processes ─────────────────────────────────────────
    echo -e "${BOLD}[ TOP 5 PROCESSES BY CPU ]${RESET}"
    get_top_processes
    echo ""

    # ── Network ───────────────────────────────────────────────
    echo -e "${BOLD}[ NETWORK CONNECTIVITY ]${RESET}"
    check_network
    echo ""

    # ── Uptime ────────────────────────────────────────────────
    echo -e "${BOLD}[ UPTIME ]${RESET}"
    echo -e "  $(uptime -p 2>/dev/null || uptime)"
    echo ""

    # ── Summary ───────────────────────────────────────────────
    echo -e "${BOLD}[ SUMMARY ]${RESET}"
    if (( ${#alerts[@]} == 0 )); then
        echo -e "  ${GREEN}All systems healthy. No thresholds breached.${RESET}"
    else
        echo -e "  ${RED}${#alerts[@]} alert(s) detected:${RESET}"
        for alert in "${alerts[@]}"; do
            echo -e "    ${RED}• ${alert}${RESET}"
            log "ALERT: $alert"
            send_slack "$(hostname): $alert — check system health"
        done
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  Report saved to: ${LOG_FILE}"
    echo -e "  Run with cron:   */5 * * * * /path/to/health_check.sh"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

main "$@"
