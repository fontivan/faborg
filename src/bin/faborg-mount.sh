#!/usr/bin/env bash
# ==============================================
# faborg-mount — Mount Borg backups
# ==============================================
# Run as root

set -euo pipefail

# -------------------------------
# Configuration
# -------------------------------
BORG_KEYFILE="/root/.borg_keyfile"
BORG_SERVER_FILE="/root/.borg_server"
MOUNT_POINT="/mnt/borg"
SSH_KEY="/root/.ssh/borg_ssh_key"

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

# -------------------------------
# Validate and parse .borg_server
# -------------------------------
validate_remote_config() {
    if [[ ! -f "${BORG_SERVER_FILE}" ]]; then
        log ERROR "Missing Borg server configuration file: ${BORG_SERVER_FILE}"
        exit 1
    fi
    local remote_line
    remote_line="$(cat "${BORG_SERVER_FILE}")"
    if ! [[ "${remote_line}" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
        log ERROR "Invalid format in ${BORG_SERVER_FILE}. Expected user@hostname:port"
        exit 1
    fi
    REMOTE_USER="${BASH_REMATCH[1]}"
    BACKUP_HOST="${BASH_REMATCH[2]}"
    BACKUP_PORT="${BASH_REMATCH[3]}"
    REMOTE="ssh://${REMOTE_USER}@${BACKUP_HOST}:${BACKUP_PORT}/backup/$(hostname)"
    log INFO "Remote configuration validated: ${REMOTE_USER}@${BACKUP_HOST}:${BACKUP_PORT}"
}

# -------------------------------
# Cleanup on exit
# -------------------------------
cleanup() {
    if mountpoint -q "${MOUNT_POINT}"; then
        log INFO "Unmounting backup from ${MOUNT_POINT}..."
        borg umount "${MOUNT_POINT}" || true
    fi
}
trap cleanup EXIT

# -------------------------------
# Main
# -------------------------------
main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log ERROR "This script must be run as root."
        exit 1
    fi

    validate_remote_config
    mkdir -p "${MOUNT_POINT}"

    if [[ ! -f "${BORG_KEYFILE}" ]]; then
        log ERROR "Missing Borg keyfile: ${BORG_KEYFILE}"
        exit 1
    fi
    export BORG_RSH="ssh -i ${SSH_KEY} -p ${BACKUP_PORT} -o StrictHostKeyChecking=no"
    export BORG_PASSPHRASE="$(cat "${BORG_KEYFILE}")"

    if ! command -v borg >/dev/null 2>&1; then
        log ERROR "borg not installed"
        exit 1
    fi

    log INFO "Listing available backups..."
    mapfile -t BACKUPS < <(borg list "${REMOTE}" | awk '{print $1}')
    if [[ ${#BACKUPS[@]} -eq 0 ]]; then
        log ERROR "No backups found"
        exit 1
    fi

    PS3="Select a backup to mount: "
    select REQUESTED_BACKUP in "${BACKUPS[@]}"; do
        [[ -n "${REQUESTED_BACKUP}" ]] && break
    done

    log INFO "Mounting backup '${REQUESTED_BACKUP}' to ${MOUNT_POINT}..."
    borg mount "${REMOTE}::${REQUESTED_BACKUP}" "${MOUNT_POINT}"
    log INFO "Backup mounted. It will be automatically unmounted on exit."
    read -rp "Press ENTER to unmount and exit..." _
}

main "$@"
