# Recovery and Security

## Restore a Backup

Restores work from the newest local archive or, after losing the host, from the offsite R2 copy; both produce the same archive file. Test the full offsite path periodically — an untested remote copy is not a backup.

### 1. Get the archive

From the local machine:

```sh
ls -lt backups/*.tar.gz | head
```

From the offsite copy (needs the `r2` and `crypt` remotes, see [offsite R2 backup setup](offsite-r2.md)):

```sh
rclone lsf crypt:             # current archives
rclone lsf crypt:previous     # archives removed by local retention (kept 30 days)
rclone copy "crypt:<kind>_vaultwarden_<timestamp>.tar.gz" ./restore
```

`<kind>` is `watch` or `scheduled`.

### 2. Stop Vaultwarden

```sh
./bin/vaultwarden-compose stop vaultwarden
```

### 3. Replace the data directory

```sh
mv data "data.lost-$(date +%Y%m%dT%H%M%SZ)"     # keep the old directory until the restore is verified
mkdir data
tar -C data -xzf "restore/<kind>_vaultwarden_<timestamp>.tar.gz"
```

If you reuse the existing `data/` instead of a fresh directory, delete `data/db.sqlite3-wal` and `data/db.sqlite3-shm` first — a stale WAL from the old database corrupts the restored one.

### 4. Verify before restarting

```sh
sqlite3 data/db.sqlite3 "PRAGMA integrity_check;"    # must print ok
```

On a host without sqlite3:

```sh
docker run --rm -v "$PWD/data:/data:ro" alpine:3.22 sh -c \
  'apk add --no-cache sqlite >/dev/null && sqlite3 /data/db.sqlite3 "PRAGMA integrity_check;"'
```

### 5. Restart and confirm

```sh
./bin/vaultwarden-compose up -d
docker compose ps       # vaultwarden healthy
```

Sign in once, confirm recent items are present, then delete the `data.lost-*` directory. The first write after the restore triggers a fresh watch backup within `BACKUP_WATCH_DEBOUNCE` seconds.

## Recovering After Losing the Host

Everything needed to rebuild lives in three places: this repository (git), the R2 bucket, and the deployment Bitwarden item. Keep next to the deployment secrets in Bitwarden:

- the rclone `crypt` password (and password2, if set) — without it the offsite archives cannot be decrypted;
- the R2 Access Key ID and Secret Access Key of the backup token.

On a new machine: install Docker and rclone, `git clone` this repository, recreate `rclone.conf` (the `[r2]` and `[crypt]` sections above), follow *Restore a Backup* from the offsite copy to rebuild `data/`, rebuild `.env` from `.env.example`, then `./bin/vaultwarden-compose up -d`.

## Security Practices

- Keep `.env`, `rclone/rclone.conf`, `data/`, `backups/`, and `logs/` private. They are excluded from Git.
- Keep sign-ups disabled except during a deliberate account provisioning window.
- `ADMIN_TOKEN` protects `/admin`; store only its Argon2id PHC hash in `.env` and Bitwarden. Generate it using `docker run --rm -it vaultwarden/server:latest /vaultwarden hash` and keep the plaintext password only in your password manager.
- A Tunnel prevents direct origin exposure, but the hostname is still internet reachable. Protect `/admin` with Cloudflare Access and MFA, maintain host updates, and test backups.
