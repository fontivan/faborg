#!/usr/bin/env bash
# ==============================================
# faborg-backup — Borg + Btrfs backup script
# Must be run as root
# ==============================================

set -euo pipefail

# -------------------------------
# Configuration
# -------------------------------
BORG_KEY="/root/.ssh/borg_ssh_key"
BORG_KEYFILE="/root/.borg_keyfile"
BORG_SERVER_FILE="/root/.borg_server"
DATE="$(date +%F)"
HOSTNAME_SHORT="$(hostname -s)"
LOCK_FILE_DIR="/etc/faborg"
LOCK_FILE="/etc/faborg/faborg.lock"
LOGFILE="/var/log/faborg.log"
SNAPSHOT_DIR_ROOT="/.snapshots"
TIMESTAMP="$(date +%F-%H%M%S)"

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
    remote_line="$(< "${BORG_SERVER_FILE}")"

    if ! [[ "${remote_line}" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
        log ERROR "Invalid format in ${BORG_SERVER_FILE}. Expected user@hostname:port"
        exit 1
    fi

    REMOTE_USER="${BASH_REMATCH[1]}"
    BACKUP_HOST="${BASH_REMATCH[2]}"
    BACKUP_PORT="${BASH_REMATCH[3]}"
    REMOTE="ssh://${REMOTE_USER}@${BACKUP_HOST}:${BACKUP_PORT}/backup/${HOSTNAME_SHORT}"

    log INFO "Remote configuration validated: ${REMOTE_USER}@${BACKUP_HOST}:${BACKUP_PORT}"
}

# -------------------------------
# Prepare Borg environment variables
# -------------------------------
prepare_borg_environment() {
    if [[ ! -f "${BORG_KEYFILE}" ]]; then
        log ERROR "Missing Borg keyfile: ${BORG_KEYFILE}"
        exit 1
    fi

    export BORG_RSH="ssh -i ${BORG_KEY} -p ${BACKUP_PORT} -o StrictHostKeyChecking=no"
    export BORG_PASSPHRASE="$(< "${BORG_KEYFILE}")"
    log INFO "Borg environment prepared"
}

# -------------------------------
# Lock functions
# -------------------------------
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(< "$LOCK_FILE")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log ERROR "Another backup process is already running (PID $pid). Exiting."
            exit 1
        else
            log WARNING "Stale lock file found. Removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
}

lock() {
    ensure_dir "$LOCK_FILE_DIR"
    check_lock
    echo $$ > "$LOCK_FILE"
    log INFO "Lock acquired (PID $$)"
}

unlock() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE")" == "$$" ]]; then
        rm -f "$LOCK_FILE"
        log INFO "Lock released (PID $$)"
    fi
}

# -------------------------------
# Btrfs helper functions
# -------------------------------
get_btrfs_device() {
    local target="$1"
    findmnt -no SOURCE --target "$target"
}

ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
    chown root:root "$dir"
    chmod 700 "$dir"
}

create_snapshot() {
    local source="$1"
    local dest="$2"
    if [[ ! -d "$dest" ]]; then
        log INFO "Creating snapshot from $source -> $dest"
        btrfs subvolume snapshot -r "$source" "$dest"
    else
        log INFO "Snapshot $dest already exists, skipping"
    fi
}

# -------------------------------
# Borg repository functions
# -------------------------------
initialize_repo() {
    log INFO "Checking if Borg repository exists..."
    if borg info "$REMOTE" >/dev/null 2>&1; then
        log INFO "Repository already exists, skipping initialization."
    else
        log INFO "Repository not found, initializing..."
        borg init --encryption=repokey-blake2 "$REMOTE"
        log INFO "Repository initialized."
    fi
}

perform_backup() {
    local root_snap="$1"
    local home_snap="$2"

    log INFO "Starting Borg backup..."
    borg create \
        --verbose \
        --stats \
        --compression zstd \
        --filter AME \
        --show-rc \
        --exclude-caches \
        "${REMOTE}::${HOSTNAME_SHORT}-${TIMESTAMP}" \
        "$root_snap" "$home_snap" \
        --exclude /proc \
        --exclude /sys \
        --exclude /dev \
        --exclude /run \
        --exclude /tmp \
        --exclude /mnt | tee -a "$LOGFILE"

    return ${PIPESTATUS[0]}
}

prune_archives() {
    log INFO "Pruning old Borg archives..."
    borg prune -v --list "$REMOTE" --keep-daily=7 --keep-weekly=4 --keep-monthly=6 | tee -a "$LOGFILE"
}

delete_snapshots() {
    local root_snap="$1"
    local home_snap="$2"

    log INFO "Deleting local snapshots..."
    btrfs subvolume delete "$root_snap" || true
    if [[ "$home_snap" != "$root_snap" ]]; then
        btrfs subvolume delete "$home_snap" || true
    fi
}

# -------------------------------
# Main function
# -------------------------------
main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log ERROR "Must be run as root"
        exit 1
    fi

    log INFO "===== Borg Backup Started ====="

    lock
    trap unlock EXIT

    validate_remote_config
    prepare_borg_environment
    initialize_repo
    ensure_dir "$SNAPSHOT_DIR_ROOT"

    ROOT_SNAP="${SNAPSHOT_DIR_ROOT}/root-${TIMESTAMP}"
    create_snapshot / "$ROOT_SNAP"

    ROOT_DEV=$(get_btrfs_device /)
    HOME_DEV=$(get_btrfs_device /home)

    if [[ "$ROOT_DEV" != "$HOME_DEV" ]]; then
        SNAPSHOT_DIR_HOME="/home/.snapshots"
        ensure_dir "$SNAPSHOT_DIR_HOME"
        HOME_SNAP="${SNAPSHOT_DIR_HOME}/home-${TIMESTAMP}"
        create_snapshot /home "$HOME_SNAP"
    else
        HOME_SNAP="${SNAPSHOT_DIR_ROOT}/home-${TIMESTAMP}"
        if btrfs subvolume show /home &>/dev/null; then
            create_snapshot /home "$HOME_SNAP"
        else
            HOME_SNAP="$ROOT_SNAP"
        fi
    fi

    perform_backup "$ROOT_SNAP" "$HOME_SNAP"
    RC=$?

    prune_archives

    if [[ $RC -eq 0 ]]; then
        delete_snapshots "$ROOT_SNAP" "$HOME_SNAP"
    fi

    log INFO "===== Borg Backup Finished ====="
    exit $RC
}

main "$@"
