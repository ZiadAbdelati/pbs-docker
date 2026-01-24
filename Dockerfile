FROM debian:bookworm-slim

# Install prerequisites, Proxmox Backup Client, and the Cron utility
RUN apt-get update && apt-get install -y wget ca-certificates cron tzdata && \
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    echo "deb http://download.proxmox.com/debian/pbs-client bookworm main" > /etc/apt/sources.list.d/pbs-client.list && \
    apt-get update && \
    apt-get install -y proxmox-backup-client && \
    rm -rf /var/lib/apt/lists/*

# Copy and set permissions for the setup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# The ENTRYPOINT runs the setup, which starts Cron
ENTRYPOINT ["/entrypoint.sh"]

# The CMD is executed by the entrypoint. We use /bin/bash to keep the container running
# while the tail -f is executed within entrypoint.sh.
CMD ["/bin/bash"]