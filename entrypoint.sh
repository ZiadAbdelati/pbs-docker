#!/bin/bash

# 1. Setup Environment Variables for PBS
export PBS_REPOSITORY="$PBS_USER@$PBS_REALM@$PBS_HOST:$PBS_DATASTORE"
export PBS_PASSWORD="$PBS_PASSWORD"
# export PBS_FINGERPRINT="$PBS_FINGERPRINT" # Uncomment if using self-signed certs without full CA setup

# 2. Define Snapshot Variables
# CephFS mounts usually support snapshots in a hidden .snap directory
SOURCE_DIR="/mnt/appdata"
SNAP_NAME="pbs-backup-$(date +%Y%m%d-%H%M%S)"
SNAP_PATH="$SOURCE_DIR/.snap/$SNAP_NAME"

echo "Starting Backup Loop..."

# Run an infinite loop to act as a scheduler (e.g., every 24h)
while true; do
    echo "[$(date)] Creating CephFS snapshot: $SNAP_NAME"
    mkdir "$SNAP_PATH"

    echo "[$(date)] Starting Proxmox Backup..."
    # We backup the SNAPSHOT path, but alias it as 'appdata' so PBS sees a consistent history
    proxmox-backup-client backup "appdata.pxar:$SNAP_PATH" \
        --backup-id "$BACKUP_ID" \
        --ns "$BACKUP_NS"

    echo "[$(date)] Removing CephFS snapshot..."
    rmdir "$SNAP_PATH"
    
    echo "[$(date)] Backup done. Sleeping for 24 hours..."
    sleep 86400 
done