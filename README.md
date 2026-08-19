# pbs-docker

A small, self-contained Docker container that runs the **Proxmox Backup Server (PBS) client** on a configurable schedule. It is designed to back up a CephFS-mounted directory (with optional CephFS snapshots) to a Proxmox Backup Server, keeping the container alive in the background and running backups automatically via `cron`.

The image is based on `debian:bookworm-slim`, installs the official Proxmox `proxmox-backup-client`, and wraps the backup job so it can be triggered either on a schedule or manually.

---

## How it works

At startup, the container's `entrypoint.sh` does the following:

1. **Builds the PBS repository string** from your environment variables
   (`PBS_USER`, `PBS_REALM`, `PBS_HOST`, `PBS_DATASTORE`) as
   `pbsuser@realm@host:datastore`.
2. **Loads the PBS password** either from the Docker secret
   `/run/secrets/pbs_password` or from the `PBS_PASSWORD` environment variable.
3. **Generates an executable backup script** (`/usr/local/bin/run_backup.sh`).
   Because `cron` runs jobs in a clean shell that does not inherit the
   container's environment variables, the script re-exports them itself.
4. **Installs a cron job** using the `CRON_SCHEDULE` variable (defaults to
   `0 3 * * *`, i.e. 03:00 every day). Cron output is redirected to PID 1 so
   it shows up in `docker logs`.
5. **Starts `cron`** and keeps the container alive in the foreground.

### The backup job

The generated backup script:

- Uses `/mnt/appdata` as the source directory.
- **Attempts a CephFS snapshot** by creating
  `/mnt/appdata/.snap/pbs-backup-YYYYMMDD-HHMMSS`. CephFS exposes snapshots
  through the `.snap` directory, so this provides a consistent point-in-time
  copy.
- If snapshot creation succeeds, the snapshot directory is backed up and then
  removed afterwards. If it fails (e.g. the source is not CephFS, or the user
  lacks permission), a **warning is printed and the live files are backed up**
  instead — the container still works on a plain mounted directory.
- Runs:

  ```bash
  proxmox-backup-client backup appdata.pxar:/path/to/source \
      --backup-id "$BACKUP_ID" \
      --ns "$BACKUP_NS"
  ```

  The archive is always named `appdata.pxar` regardless of the source so that
  backup history stays consistent across runs.

---

## Prerequisites

- A reachable **Proxmox Backup Server** with a valid datastore.
- Your data mounted (read-only is fine) at **`/mnt/appdata`** inside the
  container.
- PBS credentials with permission to write to the datastore.
- (Optional, for snapshots) a **CephFS** source mounted at `/mnt/appdata` and a
  user with permission to create snapshots, plus a CephFS layout that supports
  snapshots.

---

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `PBS_HOST` | ✅ | — | Hostname or IP of the PBS server. |
| `PBS_DATASTORE` | ✅ | — | Datastore name on the PBS server. |
| `PBS_USER` | ✅ | — | PBS user (e.g. `backup`, `root`). |
| `PBS_REALM` | ✅ | — | PBS authentication realm (e.g. `pam`, `pbs`). |
| `PBS_PASSWORD` | ⚠️* | — | PBS password. *See [Password handling](#password-handling). |
| `PBS_FINGERPRINT` | — | — | PBS server certificate fingerprint. Strongly recommended to enable TLS verification. |
| `BACKUP_ID` | — | — | Backup ID passed to `proxmox-backup-client`. |
| `BACKUP_NS` | — | — | PBS namespace to write into. |
| `CRON_SCHEDULE` | — | `0 3 * * *` | Cron schedule for automatic backups (standard 5-field cron format). |

Examples for `PBS_USER`/`PBS_REALM`: a fully qualified PBS user such as
`root@pam` corresponds to `PBS_USER=root` and `PBS_REALM=pam`.

### Password handling

You can supply the password two ways (the Docker secret takes precedence):

1. **Docker secret** at `/run/secrets/pbs_password` (recommended).
2. **`PBS_PASSWORD` environment variable**.

If neither is found, the container logs `FATAL` but still starts so you can
debug manually — backups will fail until a password is provided.

> We strongly recommend using a Docker secret or a swarm/cloud secret rather
> than a plain environment variable when possible.

---

## Usage

### Docker run

```bash
docker run -d \
  --name pbs-backup \
  -v /path/to/appdata:/mnt/appdata \
  -e PBS_HOST="pbs.example.com" \
  -e PBS_DATASTORE="backup" \
  -e PBS_USER="root" \
  -e PBS_REALM="pam" \
  -e PBS_FINGERPRINT="$(cat /path/to/server.fingerprint)" \
  -e BACKUP_ID="appdata" \
  -e BACKUP_NS="default" \
  -e CRON_SCHEDULE="0 3 * * *" \
  --secret pbs_password \
  ziadabdelati/pbs-docker
```

### Docker Compose

```yaml
services:
  pbs-backup:
    image: ziadabdelati/pbs-docker
    container_name: pbs-backup
    restart: unless-stopped
    volumes:
      - /path/to/appdata:/mnt/appdata
    environment:
      PBS_HOST: pbs.example.com
      PBS_DATASTORE: backup
      PBS_USER: root
      PBS_REALM: pam
      PBS_FINGERPRINT: "00:aa:bb:..."     # optional but recommended
      BACKUP_ID: appdata
      BACKUP_NS: default
      CRON_SCHEDULE: "0 3 * * *"
    # Uncomment to use a Docker secret instead of PBS_PASSWORD:
    # secrets:
    #   - pbs_password

secrets:
  pbs_password:
    file: ./pbs_password.txt
```

> Ready-to-copy example files are included in the repo: `docker-compose.yml.example`
> and `.env.example`. Copy `docker-compose.yml.example` to `docker-compose.yml`,
> fill in the values, then run `docker compose up -d`.

### Running a backup manually

Even while running on a schedule, you can trigger a backup on demand:

```bash
docker exec -it pbs-backup /usr/local/bin/run_backup.sh
```

### Viewing logs

```bash
docker logs -f pbs-backup
```

Both cron and the backup job write to the container's stdout/stderr, so they
appear in `docker logs`.

---

## Cron schedule format

`CRON_SCHEDULE` accepts the standard 5-field cron syntax:

```
minute hour day-of-month month day-of-week
```

Examples:

| Schedule | Meaning |
| --- | --- |
| `0 3 * * *` | 03:00 every day (default) |
| `0 */6 * * *` | Every 6 hours |
| `30 2 * * 1` | 02:30 every Monday |
| `0 1 * * 0` | 01:00 every Sunday |

The container automatically strips surrounding quotation marks from the value,
so `CRON_SCHEDULE="0 3 * * *"` (with quotes) works correctly.

---

## Building the image locally

```bash
docker build -t pbs-docker .
```

Then run it as shown above, replacing `ziadabdelati/pbs-docker` with
`pbs-docker`.

---

## Building & pushing with GitHub Actions

The repository includes a manual workflow at
`.github/workflows/build-and-push.yml` that builds and pushes the image.

Run it from the **Actions** tab → **Build & Push Docker Image (manual)** →
**Run workflow**, optionally supplying:

- **registry** — `ghcr.io` (default) or `docker.io` for Docker Hub.
- **image_name** — defaults to `<owner>/<repo>`.
- **tag** — tag to push; if blank it uses the short Git SHA (and `latest` if
  `push_latest` is enabled).
- **push_latest** — also push `:latest` (default `true`).

For GHCR, authentication uses the built-in `GITHUB_TOKEN` automatically. For
other registries (e.g. Docker Hub), configure the `REGISTRY_USERNAME` and
`REGISTRY_PASSWORD` repository secrets. The image is built with Docker Buildx
and uses GitHub Actions cache (`type=gha`) for faster rebuilds.

---

## Notes & limitations

- **CephFS snapshots** require a CephFS source mounted at `/mnt/appdata` and
  snapshot permission. On any other filesystem, the script logs a warning and
  falls back to a live backup.
- The backup source directory is hard-coded to `/mnt/appdata`. Mount your data
  there (e.g. via `docker run -v` or the compose `volumes:` key).
- Timezone support is included (`tzdata`) so `CRON_SCHEDULE` follows the
  container's local timezone. Set `TZ` if you need a timezone other than UTC.

