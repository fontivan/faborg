#!/usr/bin/env bash
# ==============================================
# faborg-install — Install and configure faborg
# ==============================================
# Run as a regular user (sudo for root operations)

set -euo pipefail

# -------------------------------
# Configuration
# -------------------------------
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ROOT_SSH_DIR="/root/.ssh"
BORG_KEY="${ROOT_SSH_DIR}/borg_ssh_key"
BORG_KEYFILE="/root/.borg_keyfile"
BORG_SERVER_FILE="/root/.borg_server"
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

# -------------------------------
# Validate and parse .borg_server
# -------------------------------
validate_remote_config() {
    if ! remote_line=$(sudo cat "${BORG_SERVER_FILE}" 2>/dev/null); then
        log ERROR "Cannot read ${BORG_SERVER_FILE} — make sure it exists and is readable via sudo"
        exit 1
    fi
    if ! [[ "${remote_line}" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
        log ERROR "Invalid format in ${BORG_SERVER_FILE}. Expected user@hostname:port"
        exit 1
    fi
    REMOTE_USER="${BASH_REMATCH[1]}"
    BACKUP_HOST="${BASH_REMATCH[2]}"
    BACKUP_PORT="${BASH_REMATCH[3]}"
    REMOTE="${REMOTE_USER}@${BACKUP_HOST}"
    log INFO "Remote configuration validated: ${REMOTE_USER}@${BACKUP_HOST}:${BACKUP_PORT}"
}

# -------------------------------
# Configure root SSH keys and Borg keyfile
# -------------------------------
configure_root_keys() {
    log INFO "Configuring root SSH keys..."
    sudo mkdir -p "${ROOT_SSH_DIR}" && sudo chmod 700 "${ROOT_SSH_DIR}"

    if sudo test -f "${BORG_KEY}"; then
        log INFO "Root Borg SSH key already exists; using existing key."
    else
        log INFO "Generating new root Borg SSH key..."
        sudo ssh-keygen -t ed25519 -f "${BORG_KEY}" -N "" || {
            log ERROR "Failed to generate root Borg SSH key."
            exit 1
        }
    fi

    if ! sudo test -f "${BORG_KEY}.pub"; then
        log ERROR "Root SSH public key missing!"
        exit 1
    fi

    if ! sudo test -f "${BORG_KEYFILE}"; then
        if [[ -f "${SCRIPT_DIR}/../etc/faborg/.borg_keyfile" ]]; then
            log INFO "Installing Borg passphrase keyfile..."
            sudo cp "${SCRIPT_DIR}/../etc/faborg/.borg_keyfile" "${BORG_KEYFILE}"
            sudo chmod 600 "${BORG_KEYFILE}"
            sudo chown root:root "${BORG_KEYFILE}"
        else
            log ERROR "Source Borg keyfile missing!"
            exit 1
        fi
    else
        log INFO "Borg passphrase keyfile already exists; using existing keyfile."
    fi
}

# -------------------------------
# Install local script and systemd
# -------------------------------
install_local_script() {
    log INFO "Installing local backup script..."
    sudo install -o root -g root -m 700 "${SCRIPT_DIR}/faborg-backup.sh" /usr/local/bin/faborg-backup.sh
    sudo install -o root -g root -m 700 "${SCRIPT_DIR}/faborg-mount.sh" /usr/local/bin/faborg-mount.sh
}

install_systemd() {
    log INFO "Installing systemd service and timer..."
    sudo cp "${SCRIPT_DIR}/../etc/faborg.service" /etc/systemd/system/
    sudo cp "${SCRIPT_DIR}/../etc/faborg.timer" /etc/systemd/system/
    sudo cp "${SCRIPT_DIR}/../etc/logrotate.conf" /etc/logrotate.d/faborg
    sudo systemctl daemon-reload
    sudo systemctl enable --now faborg.timer
    sudo systemctl status faborg.timer --no-pager || true
}

# -------------------------------
# Main
# -------------------------------
main() {
    validate_remote_config
    configure_root_keys
    install_local_script
    install_systemd
    log INFO "faborg installation complete."
}

main "$@"
