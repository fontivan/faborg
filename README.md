# Faborg — Fedora Automated Borg Backup

Faborg (Fontivan Auto Borg) is a set of scripts to automate backups on Fedora systems using Btrfs snapshots and BorgBackup. It simplifies setup, backup, mounting, and maintenance of Borg repositories, with minimal manual intervention.

# #Features

- Automated root SSH key and Borg key setup
- Secure upload of root SSH public key to NAS/backup server
- Local backup scripts installed for easy execution
- Systemd timer integration for scheduled backups
- Btrfs snapshot management with automatic cleanup
- Interactive mounting of Borg repositories for inspection

## Repository Structure

```bash
faborg/
├─ src/
│  └─ bin/
│     ├─ faborg-install.sh       # Install/setup script
│     ├─ faborg-backup.sh        # Backup execution script
│     └─ faborg-mount.sh         # Mount a backup snapshot interactively
├─ etc/
│  └─ faborg/
│     ├─ .borg_keyfile           # Borg passphrase file
│     ├─ faborg-backup.sh        # Template backup script
│     ├─ faborg.service          # Systemd service unit
│     ├─ faborg.timer            # Systemd timer unit
│     └─ logrotate.conf          # Log rotation for backups
└─ README.txt
```

## Prerequisites

- Compatible Linux system (tested on Fedora 42+)
- Btrfs filesystem for snapshot support
- BorgBackup installed (sudo dnf install borgbackup)
- SSH access to a Borg/NAS server for backups
- User running the install script must have sudo access

### Setup

1. It is assumed that a Borg server is already set up and available over the network.

2. Populate your secret configuration
```bash
echo "mysecretpassword" | sudo tee -a /root/.borg_keyfile
echo "borg@192.168.100.100:2222" | sudo tee -a /root/.borg_server
```

3. Run the install script
```bash
   ./src/bin/faborg-install.sh
```

The script will:
   - Validate the Borg server configuration
   - Generate or reuse root SSH keys
   - Install local backup scripts and systemd timer

4. Copy the generated public key to your Borg server's sshkeys folder and save is using the system's hostname as the file name

### Backup Execution

The backup script must be run as root:
```bash
sudo /usr/local/bin/faborg-backup.sh
```

The script handles:
- Create Btrfs snapshots for / and /home (if separate)
- Push the snapshots to the Borg repository
- Prune old archives based on daily/weekly/monthly retention
- Delete local snapshots after a successful backup

### Mounting a Backup

Use the mount script to browse a specific backup snapshot:
```bash
sudo /usr/local/bin/faborg-mount.sh
```

This script lists available backups interactively and mounts the selected backup under /mnt/borg.

When finished, unmount:
```bash
sudo borg umount /mnt/borg
```

### Logging

Logs are stored at /var/log/faborg.log.

The systemd timer also captures logs via:

```bash
journalctl -u faborg.timer
```

### Systemd Integration

After install, faborg.timer runs automatically to schedule backups.

Check timer status:
```bash
systemctl status faborg.timer
```

Manually trigger backup service:
```bash
systemctl start faborg.service
```

## Security Notes

- Root SSH keys and the Borg keyfile are stored under /root/.ssh/ and /root/.borg_keyfile.
- Always secure your .borg_keyfile — it is the encryption key for your backups.

## Contributing

1. Fork the repository
2. Make your changes in a branch
3. Submit a pull request

## License

See LICENSE file.
