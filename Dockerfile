FROM debian:bookworm-slim

# Install prerequisites and Proxmox Backup Client
RUN apt-get update && apt-get install -y wget ca-certificates && \
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    echo "deb http://download.proxmox.com/debian/pbs-client bookworm main" > /etc/apt/sources.list.d/pbs-client.list && \
    apt-get update && \
    apt-get install -y proxmox-backup-client cron && \
    rm -rf /var/lib/apt/lists/*

# Add your backup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]