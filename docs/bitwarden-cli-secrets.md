# Bitwarden CLI Secrets

The `bin/vaultwarden-compose` launcher reads sensitive runtime values from Bitwarden CLI, then starts Docker Compose. It currently reads `ADMIN_TOKEN` and `CLOUDFLARE_TUNNEL_TOKEN` from a Bitwarden item. It never writes a decrypted secret to a file.

`.env` remains required as a private, ignored break-glass fallback. Keep it complete and current so Vaultwarden can start if Bitwarden CLI is unavailable, the vault cannot be unlocked, or the Bitwarden service is unavailable. This matters because the Vaultwarden `ADMIN_TOKEN` may itself be stored in Bitwarden.

## Prerequisites

- Install the Bitwarden Password Manager CLI (`bw`) and `jq` on the Docker host.
- Log the CLI in to the Bitwarden account which stores the deployment secrets. For a self-hosted Bitwarden/Vaultwarden server, configure the CLI server first with `bw config server https://<VAULTWARDEN_DOMAIN>`.
- Unlock the CLI and export its session key in the current terminal:

  ```sh
  export BW_SESSION="$(bw unlock --raw)"
  ```

The session is temporary and is invalidated by `bw lock`, `bw logout`, or CLI session expiration.

## Create the Deployment Item

1. In Bitwarden, create a **Secure Note** named `Vaultwarden Deployment`.
1. Add custom hidden fields with these exact names:
   - `ADMIN_TOKEN`: the Argon2id PHC hash protecting Vaultwarden `/admin`, not its plaintext password. Generate it with `docker run --rm -it vaultwarden/server:latest /vaultwarden hash`, enter the plaintext password only at the prompt, and save the returned `$argon2id$...` string.
   - `CLOUDFLARE_TUNNEL_TOKEN`: the token from Cloudflare Zero Trust for this tunnel.
1. Save the item and run `bw sync`.

To use a different item name, set `BITWARDEN_ITEM_NAME` before calling the launcher:

```sh
export BITWARDEN_ITEM_NAME="My Vaultwarden Production Secrets"
```

## Use the Launcher

Replace `docker compose` with `./bin/vaultwarden-compose` for commands that start, recreate, or inspect the stack:

```sh
./bin/vaultwarden-compose up -d
./bin/vaultwarden-compose logs -f vaultwarden cloudflared
./bin/vaultwarden-compose ps
```

Docker Compose loads non-secret settings from `.env`. The launcher separately reads only the two fallback secret values, without interpreting the file as shell code, so standard Compose values such as unquoted cron schedules remain compatible. When `bw`, `jq`, and an unlocked `BW_SESSION` are present, Bitwarden values override the two fallback values for that command only.

After a successful `up` or `start`, the launcher automatically runs `bw lock`. A child process cannot remove `BW_SESSION` from your current shell, so run `unset BW_SESSION` after the command. If `up` or `start` fails, the launcher prints the explicit `bw lock && unset BW_SESSION` cleanup command instead.

## Break-Glass Recovery

Use the regular Docker Compose command if Bitwarden CLI is unavailable or cannot be unlocked:

```sh
docker compose up -d
```

This command gets every value from `.env`. Protect it with `chmod 600 .env`, keep it out of Git, and update its two secrets whenever the corresponding Bitwarden item changes. `ADMIN_TOKEN` in `.env` must be the exact Argon2id PHC hash stored in Bitwarden, not the plaintext password. Test this recovery path periodically.
