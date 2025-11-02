#!/usr/bin/env bash
# ==============================================
# faborg-halt - Stop an in progress backup
# ==============================================
# Run as a regular user (sudo for root operations)

set -eou pipefail

LOCK_FILE="/etc/faborg/faborg.lock"
LOGFILE="/var/log/faborg.log"

# -------------------------------
# Logging function
# -------------------------------
log() {
    local level="${1:-INFO}"
    shift
    local msg="${*}"
    local timestamp
    timestamp="$(date '+%F %T')"
    local line="[${timestamp}] [${level}] ${msg}"
    # Output to stdout and append to log file
    echo "$line" | sudo tee -a "$LOGFILE"
}

main() {
    log INFO "===== Borg Halt Started ====="
    if sudo test -f "${LOCK_FILE}"; then
        LOCK_PID="$(sudo cat ${LOCK_FILE})"
        log INFO "Halting in progress process '${LOCK_PID}'"
        sudo kill ${LOCK_PID}
    else
        log INFO "No in progress backup detected"
    fi
}

main
