#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ -f .env.production ]]; then env_file=.env.production; elif [[ -f .env ]]; then env_file=.env; else echo "Create .env.production or .env first" >&2; exit 1; fi
compose=(docker compose --env-file "$env_file" -p btek-infra)
mkdir -p -m 700 backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
db_backup="backups/keycloak-${stamp}.dump"
rustfs_backup="backups/rustfs-${stamp}.tar.gz"
rustfs_id=$("${compose[@]}" ps -q rustfs)
if [[ -z "$rustfs_id" ]]; then echo "RustFS container is not present" >&2; exit 1; fi
umask 077
"${compose[@]}" exec -T keycloak-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$db_backup"
"${compose[@]}" stop rustfs
restart_rustfs() { "${compose[@]}" start rustfs >/dev/null; }
trap restart_rustfs EXIT
docker run --rm --volumes-from "${rustfs_id}:ro" -v "$PWD/backups:/backup" -e BACKUP_FILE="$(basename "$rustfs_backup")" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" alpine:3.24 sh -c 'umask 077; tar -czf "/backup/$BACKUP_FILE" -C /data .; chown "$HOST_UID:$HOST_GID" "/backup/$BACKUP_FILE"'
restart_rustfs
trap - EXIT
chmod 600 "$db_backup" "$rustfs_backup"
sha256sum "$db_backup" "$rustfs_backup" > "backups/${stamp}.sha256"
chmod 600 "backups/${stamp}.sha256"
printf 'Created %s and %s\n' "$db_backup" "$rustfs_backup"
