# Offsite R2 Backup Setup

`backup-sync` encrypts every archive with an rclone `crypt` remote and mirrors the local `backups/` directory to Cloudflare R2 on `BACKUP_SYNC_SCHEDULE` (every ten minutes by default). This page is the once-per-host setup plus the errors each misconfiguration produces.

## 1. Create the R2 bucket and API token

In the Cloudflare dashboard under R2:

1. Create a bucket, for example `vaultwarden-backups`.
1. Manage R2 API Tokens → Create API Token with **Object Read & Write**, scoped to **only that bucket**. Copy the **Access Key ID** and **Secret Access Key**; the "Token value" shown on the same page is not used by S3 clients, and the secret is displayed only once.
1. Note the **Account ID** from the R2 overview sidebar; it is part of the S3 endpoint.

A bucket-scoped token deliberately cannot perform account-level operations. Consequences you will see and should expect:

- `rclone lsd r2:` (ListBuckets) fails with `AccessDenied` — always test against the bucket itself: `rclone lsd r2:vaultwarden-backups`.
- rclone must not probe or create buckets — hence `no_check_bucket` below.

## 2. Configure the two rclone remotes

On the Docker host, `rclone config` → new remote `r2` (type `s3`):

| Field | Value |
|---|---|
| provider | Cloudflare |
| access_key_id / secret_access_key | from the token above |
| endpoint | `https://<account_id>.r2.cloudflarestorage.com` — required; if left empty rclone sends the R2 keys to real AWS S3 |
| no_check_bucket | `true` — the bucket-scoped token cannot create or probe buckets |

Then a second remote `crypt` wrapping the bucket:

| Field | Value |
|---|---|
| type | crypt |
| remote | `r2:vaultwarden-backups` |
| password | a long random value — **store it in Bitwarden; without it the offsite archives cannot be decrypted** |
| filename_encryption | standard (default) |

Resulting `~/.config/rclone/rclone.conf` (rclone obscures the secrets):

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = ...
secret_access_key = ...
endpoint = https://<account_id>.r2.cloudflarestorage.com
no_check_bucket = true

[crypt]
type = crypt
remote = r2:vaultwarden-backups
password = ...
```

Because the crypt remote already points at the bucket, the deployment uses `RCLONE_REMOTE=crypt:`. Appending a path (`crypt:vaultwarden-backups`) nests every archive one encrypted directory deeper inside the bucket.

Verify before wiring it up — both commands must finish without errors:

```sh
rclone lsd r2:vaultwarden-backups   # empty bucket: no output
rclone lsd crypt:                   # same through the crypt layer
```

## 3. Wire up and start the tier

In `.env` (the config path must be the **directory** containing rclone.conf, not the file):

```sh
RCLONE_REMOTE=crypt:
RCLONE_CONFIG_HOST=/absolute/path/to/rclone/config/dir
```

Then:

```sh
./bin/vaultwarden-compose up -d --force-recreate backup-sync
./bin/vaultwarden-compose exec backup-sync sh /scripts/backup-sync.sh   # first sync
rclone lsf crypt:                   # the archives, encrypted names
docker compose ps                   # backup-sync turns healthy within ~10 minutes
```

Credential changes to rclone.conf propagate into the running container immediately (bind mount); changes to `RCLONE_REMOTE` need the container recreated.

## Misconfiguration symptoms

Every error below was produced by a real misconfiguration; match the message, apply the fix.

| Error | Cause | Fix |
|---|---|---|
| `InvalidAccessKeyId ... does not exist in our records` | empty `endpoint`: rclone sent the Cloudflare keys to real AWS S3 | set `endpoint` to `https://<account_id>.r2.cloudflarestorage.com` |
| `AccessDenied` on `rclone lsd r2:` | `ListBuckets` is account-level; the bucket-scoped token denies it by design | expected — list the bucket itself instead |
| `S3: CreateBucket ... 403 AccessDenied` during sync | rclone tried to probe/create the bucket, which the token cannot do | `rclone config update r2 no_check_bucket true` |
| `Failed to create file system ... is a file not a directory` (crypt) | symptom, not cause: every underlying S3 call is failing (auth/endpoint) | fix the error above first; this one follows |
| `rclone config not found at /config/rclone/rclone.conf` | `RCLONE_CONFIG_HOST` points at the rclone.conf **file**; compose mounted it where a directory belongs | set it to the directory containing the file |
| `WARN ... "ADMIN_TOKEN" variable is not set` | plain `docker compose` renders the vaultwarden service with unset variables | harmless for backup commands; `./bin/vaultwarden-compose` silences it |
