#!/bin/bash

# --- 1. SETUP ENVIRONMENT & SECRETS ---

# Construct the repository string required by PBS
# If any of these are missing, the script will fail gracefully.
export PBS_REPOSITORY="$PBS_USER@$PBS_REALM@$PBS_HOST:$PBS_DATASTORE"

# Handle Docker Secrets (if used), otherwise fallback to Env Var
if [ -f "/run/secrets/pbs_password" ]; then
    export PBS_PASSWORD=$(cat /run/secrets/pbs_password)
elif [ -n "$PBS_PASSWORD" ]; then
    export PBS_PASSWORD="$PBS_PASSWORD"
else
    echo "FATAL: PBS_PASSWORD environment variable or Docker secret not found!"
    # Allow the script to proceed for manual debugging, but backups will fail.
fi

# --- 2. CREATE THE EXECUTABLE BACKUP SCRIPT ---

# We write the logic to a separate file so Cron can call it cleanly
cat <<EOF > /usr/local/bin/run_backup.sh
#!/bin/bash
# Export vars again because Cron runs in a clean shell and doesn't inherit them
export PBS_REPOSITORY="$PBS_REPOSITORY"
export PBS_PASSWORD="$PBS_PASSWORD"
export PBS_FINGERPRINT="$PBS_FINGERPRINT"
export BACKUP_ID="$BACKUP_ID"
export BACKUP_NS="$BACKUP_NS"

SOURCE_DIR="/mnt/appdata"
SNAP_NAME="pbs-backup-\$(date +\%Y\%m\%d-\%H\%M\%S)" # Escape % for the cat command
SNAP_PATH="\$SOURCE_DIR/.snap/\$SNAP_NAME"

echo "[$(date)] --- Starting Proxmox Backup ---"

# --- SNAPSHOT CREATION ---
echo "[$(date)] Attempting to create snapshot: \$SNAP_NAME"

# Attempt to create the snapshot directory
if mkdir "\$SNAP_PATH" 2>/dev/null; then
    echo "[$(date)] CephFS snapshot created successfully. Backing up snapshot."
    TARGET_PATH="\$SNAP_PATH"
    USE_SNAPSHOT=1
else
    echo "WARNING: Snapshot creation failed (Permission or Config issue). Backing up LIVE files."
    TARGET_PATH="\$SOURCE_DIR"
    USE_SNAPSHOT=0
fi

# --- PBS CLIENT EXECUTION ---
echo "[$(date)] Running Proxmox Backup Client..."
# We map the backup root to 'appdata.pxar' regardless of source so the history stays consistent
proxmox-backup-client backup "appdata.pxar:\$TARGET_PATH" \\
    --backup-id "\$BACKUP_ID" \\
    --ns "\$BACKUP_NS"

# --- CLEANUP ---
if [ "\$?" -eq 0 ]; then
    echo "[$(date)] Backup completed successfully."
else
    echo "ERROR: Backup failed with code \$?."
fi

if [ "\$USE_SNAPSHOT" -eq 1 ]; then
    echo "[$(date)] Removing snapshot: \$SNAP_PATH"
    rmdir "\$SNAP_PATH"
fi

echo "[$(date)] --- Backup Finished ---"
EOF

# Make the generated script executable
chmod +x /usr/local/bin/run_backup.sh

# --- 3. SETUP CRON SCHEDULER ---

# Default to 3:00 AM daily if CRON_SCHEDULE variable is not set
SCHEDULE=${CRON_SCHEDULE:-"0 3 * * *"}

echo "Setting up cron job with schedule: $SCHEDULE"

# Write crontab. Redirect stdout/stderr to PID 1 so you see logs in 'docker logs'
echo "$SCHEDULE root /usr/local/bin/run_backup.sh > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/cron.d/pbs-backup
chmod 0644 /etc/cron.d/pbs-backup
crontab /etc/cron.d/pbs-backup

# --- 4. START CRON AND KEEP CONTAINER ALIVE ---

echo "Container started. Starting Cron in background..."
/usr/sbin/cron

echo "Cron is running. Backups are scheduled to run at $SCHEDULE."
echo "To trigger a backup manually, run: docker exec -it <container> /usr/local/bin/run_backup.sh"

# Keep the container running in the foreground to prevent Docker from stopping it
# The 'tail -f' command keeps PID 1 alive and the logs flowing.
exec tail -f /dev/null