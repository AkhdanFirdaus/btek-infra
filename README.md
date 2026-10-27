# btek-infra

Infrastructure ini memiliki siklus deploy sendiri: Caddy, Keycloak dengan PostgreSQL khusus, dan RustFS. Keycloak dimulai kosong; realm aplikasi tetap dikelola btek-docs dan baru diprovision setelah kedua stack siap.

## Konfigurasi dan deploy

Host infra adalah `https://sso.bteklabs.com`, `https://s3.bteklabs.com`, dan `https://storage.bteklabs.com`. Hostname aplikasi `https://desk.bteklabs.com` dirutekan Caddy ke alias `btek-docs-app:3000` pada network bersama `proxy`; nilai `APP_PUBLIC_URL` tetap dikonfigurasi oleh repo btek-docs.

Workflow `.github/workflows/deploy-infra.yml` memakai GitHub Environment `production`, berjalan manual atau dari tag `infra-v*`, dan hanya mengubah stack infra. Atur `DEPLOY_PATH=/opt/infra`. Workflow memakai variable dan secret berikut:

Variables: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, `DEPLOY_PORT`, `KEYCLOAK_PUBLIC_URL`, `RUSTFS_S3_PUBLIC_URL`, `RUSTFS_CONSOLE_PUBLIC_URL`, `POSTGRES_ADMIN_USER`, `KEYCLOAK_ADMIN_USERNAME`.

Secrets: `DEPLOY_SSH_PRIVATE_KEY`, `DEPLOY_KNOWN_HOSTS`, `POSTGRES_ADMIN_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `RUSTFS_ACCESS_KEY_ID`, `RUSTFS_SECRET_ACCESS_KEY`. Dua secret RustFS dipetakan menjadi root credential saat bootstrap. Jangan bagikan root credential ke btek-docs.

Untuk bootstrap manual, siapkan `.env.production` dari `.env.example`, buat network bersama, lalu:

```sh
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker compose --env-file .env.production -p btek-infra up -d --wait
docker compose --env-file .env.production -p btek-infra ps
```

Hanya Caddy mempublikasikan port host 80/443. PostgreSQL tetap pada network privat. Route `desk.bteklabs.com` dilayani Caddy dari repo infra. Compose produksi btek-docs bergabung ke network `proxy` memakai alias unik `btek-docs-app`; workflow infra memuat ulang konfigurasi Caddy setelah deploy.

## RustFS bucket dan akses app

Setelah deployment dan health check lulus, login ke `https://storage.bteklabs.com` memakai root credential infra. Buat bucket `btek-docs`, lalu buat IAM user induk `btek-docs-app`. Tambahkan policy dari [`policies/btek-docs-bucket.json`](policies/btek-docs-bucket.json) pada IAM user itu, lalu buat service account dan simpan access key-nya hanya di GitHub Environment repo btek-docs. Policy membatasi list bucket dan read/write/delete object pada bucket tersebut. RustFS service account mewarisi policy induknya; root hanya untuk bootstrap/break-glass. Lihat [panduan IAM RustFS](https://docs.rustfs.com/en/security-compliance/iam) dan [format policy](https://docs.rustfs.com/en/security-compliance/iam/policies).

Bucket dan credential belum dibuat oleh workflow karena tindakan itu baru bisa dilakukan setelah RustFS tersedia. Tidak ada data lama yang dipindahkan.

Keycloak tersedia di `https://sso.bteklabs.com`. Gunakan admin bootstrap hanya untuk administrasi infra. Setelah infra dan app btek-docs sama-sama terdeploy, jalankan provisioning realm dari repository btek-docs.

## Health, backup, dan restore

`docker compose ps` menampilkan health PostgreSQL, readiness Keycloak `/health/ready`, health RustFS API, dan validasi konfigurasi Caddy. Lihat log dengan `docker compose --env-file .env.production -p btek-infra logs --since=10m caddy keycloak keycloak-db rustfs`.

Jalankan `./scripts/backup.sh` dari checkout infra di server. Script membuat dump PostgreSQL dan arsip volume RustFS di `backups/`; RustFS dihentikan hanya selama snapshot dan dinyalakan lagi otomatis. Pindahkan backup terenkripsi ke lokasi terpisah dari server.

Latihan restore dilakukan hanya di host Docker terisolasi, bukan dengan menimpa volume produksi. Salin `.env.production` dan backup ke host itu. Restore PostgreSQL ke volume proyek baru:

```sh
docker compose --env-file .env.production -p btek-infra-restore up -d keycloak-db
docker compose --env-file .env.production -p btek-infra-restore exec -T keycloak-db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --no-acl' < backups/keycloak-BACKUP_TIMESTAMP.dump
```

Pada host latihan, buat network eksternal `proxy` terlebih dahulu. Untuk RustFS, ekstrak arsip ke volume proyek latihan yang baru sebelum memulai service:

```sh
docker volume create btek-infra-restore_rustfs_data
docker run --rm -v btek-infra-restore_rustfs_data:/data -v "$PWD/backups:/backup:ro" alpine:3.24 sh -c 'tar -xzf /backup/rustfs-BACKUP_TIMESTAMP.tar.gz -C /data'
docker compose --env-file .env.production -p btek-infra-restore up -d rustfs
```

Ganti `BACKUP_TIMESTAMP` dengan nama backup yang benar. Jangan gunakan project atau volume `btek-infra` produksi untuk latihan restore.
