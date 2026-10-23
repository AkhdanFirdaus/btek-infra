# Rencana pemisahan service btek-docs dan btek-infra

Dasar: [20261023-separate-services.md](./20261023-separate-services.md), konfigurasi kedua repo pada 23 Oktober 2026, dan klarifikasi bahwa aplikasi masih tahap awal. Ini rencana pelaksanaan; belum ada service produksi yang dipindahkan.

## Keputusan

- `btek-infra` memiliki Caddy, Keycloak dengan PostgreSQL khusus Keycloak, dan RustFS. `btek-docs` memiliki app, worker, migrator, dan PostgreSQL aplikasi.
- Keycloak dan RustFS infra dimulai **baru/kosong**. Tidak ada migrasi database Keycloak, user, bucket, atau objek RustFS lama. Database aplikasi tetap mengikuti kebutuhan deployment `btek-docs`; rencana ini tidak mengasumsikan isinya kosong.
- Definisi realm `btek`, client `btek-docs-app`, role, redirect URI, web origin, dan secret client tetap dimiliki `btek-docs`. **Setelah infra dan app berhasil di-deploy**, jalankan langkah provisioning untuk mengirim konfigurasi tersebut ke Keycloak infra. Provisioning harus aman dijalankan ulang, hanya mengubah resource yang dimiliki `btek-docs`, dan tidak menghapus client aplikasi lain.
- Hostname publik tetap menjadi issuer OIDC kanonis. App memakai endpoint internal pada Docker network bersama untuk komunikasi server-ke-server. Hanya Caddy membuka port publik 80/443; database tetap pada network privat.
- Semua repository deployment (termasuk btek-infra dan btek-docs) memakai akun deployment bersama; tiap repository mendapat direktori sendiri di /opt/apps/<repository>. Alur lokal harus tetap jelas sebelum service lama dihapus dari Compose aplikasi.

## Temuan repository

- `btek-docs-app/compose.yaml` saat ini memuat app, worker, migrator, PostgreSQL, Keycloak `26.8.1`, dan RustFS `1.0.3`. PostgreSQL saat ini menyediakan database `btek_docs` dan `keycloak` dalam satu instance.
- `compose.edge.yaml` menambahkan Caddy dan setelan produksi; `Caddyfile` merutekan app, SSO, S3, dan konsol storage. Workflow `.github/workflows/deploy-release.yml` mengunggah semua konfigurasi itu dari repo app.
- `keycloak/start-keycloak.sh` menjalankan import template realm ketika Keycloak mulai dengan `--override false`. Pola ini perlu diganti: Keycloak infra boleh mulai tanpa konfigurasi app, lalu konfigurasi app dikirim setelah kedua deployment siap.
- Skrip backup Keycloak mengasumsikan service ada di Compose app. Backup aplikasi juga mengasumsikan RustFS dapat diakses dari Compose app. Perintah dan dokumentasi perlu disesuaikan dengan pemisahan stack.

## Checklist

### 0. Persiapan

- [x] Petakan service, Compose, Caddy, workflow, template realm, dan asumsi backup pada kedua repo.
- [x] Tetapkan bahwa Keycloak/RustFS infra dimulai kosong; tidak ada migrasi data Keycloak/RustFS lama.
- [x] Periksa Docker lokal WSL: Docker Engine 29.4.3, Compose v5.1.3; Compose project btek-docs-app memakai volume btek-docs-app_btek_docs_postgres dan btek-docs-app_btek_docs_rustfs; network saat ini btek-docs-app_default, belum ada network bersama. Keycloak 26.8.1, RustFS 1.0.3, dan PostgreSQL 17.11 terdeteksi. App dan worker lokal berstatus exited (137) saat pemeriksaan; migrator selesai, DB/Keycloak/RustFS sehat.
- [x] Catat kapasitas mesin WSL lokal: sekitar 16 GB memori Docker dan 823 GB disk bebas pada filesystem proyek. Angka ini hanya untuk lingkungan lokal, bukan server produksi.
- [x] Tetapkan proposal awal deployment path /opt/infra untuk stack infra dan /opt/apps/btek-docs untuk stack app; nama network bersama yang diusulkan proxy.
- [x] Inventaris secret infra tanpa membaca nilainya: password admin dan user DB Keycloak, password admin bootstrap Keycloak, access key bootstrap RustFS, SSH deploy key, dan host key.
- [x] User mengonfirmasi DNS dan host produksi sudah sesuai; domain publik menggunakan *.bteklabs.com tanpa embel-embel libra. Nama layanan infra: sso.bteklabs.com, storage.bteklabs.com, dan s3.bteklabs.com.
- [x] Tetapkan GitHub Environment production pada repository btek-infra sebagai tempat secret dan variable deployment infra; pemilik operasionalnya maintainer repository/environment. Jangan simpan secret di Git.
- [x] User mengonfirmasi seluruh variable dan secret btek-infra sudah dimasukkan ke GitHub Environment production. Nilai secret tidak dibaca atau dicatat di repository.
- [x] Tetapkan jendela deploy standar: Selasa–Kamis pukul 19.00–21.00 ICT (UTC+7), di luar jam kerja dan dengan dua jam untuk verifikasi/rollback. Tanggal spesifik dipilih setelah latihan deployment lulus.

### 1. Bangun btek-infra

- [x] Buat Compose terpisah untuk Caddy, Keycloak + PostgreSQL khususnya, dan RustFS dengan image dipin. Buat Docker network eksternal bersama serta network privat database.
- [x] Pindahkan konfigurasi Caddy agar merutekan tiga hostname layanan infra pada network bersama. Hanya Caddy membuka 80/443.
- [x] Jalankan Keycloak produksi tanpa import realm `btek` saat startup. Siapkan endpoint/admin credential yang diperlukan oleh langkah provisioning dari `btek-docs`.
- [x] Siapkan service RustFS baru/kosong dengan volume persisten, image dipin, dan health check; dokumentasikan pembuatan bucket serta aksesnya.
- [ ] Setelah deployment, buat bucket `btek-docs` dan IAM user/service account app dengan policy terbatas. Ini tindakan operasional maintainer.
- [x] Buat `.env.example`, dokumentasi bootstrap, health check, backup/restore untuk data infra yang **dibuat setelah deployment**, serta jalur deploy infra independen dari release app.

### 2. Ubah btek-docs menjadi konsumen

- [ ] Ubah Compose produksi agar hanya mengelola app, worker, migrator, dan PostgreSQL aplikasi. Hapus `depends_on` lintas Compose dan gunakan kesiapan/retry koneksi yang sesuai.
- [ ] Arahkan `KEYCLOAK_INTERNAL_URL` dan `RUSTFS_ENDPOINT` ke service infra pada network bersama. Pertahankan `KEYCLOAK_PUBLIC_URL` sebagai issuer HTTPS kanonis dan callback app pada hostname publik.
- [ ] Tambahkan route hostname aplikasi ke Caddy ingress setelah app domain ditetapkan; definisi hostname dan workflow deploy app tetap dimiliki repo btek-docs.
- [ ] Untuk instalasi PostgreSQL baru, ubah skrip init agar hanya membuat database/role aplikasi. Tentukan penanganan instance lama secara terpisah bila memang digunakan.
- [ ] Pertahankan konfigurasi realm/client/role milik app di repo `btek-docs`. Buat perintah provisioning pasca-deploy yang membuat atau memperbarui hanya konfigurasi itu di Keycloak infra, aman diulang, tidak membawa user lama, dan gagal jelas bila credential/admin API tidak tersedia.
- [ ] Ubah workflow rilis app agar hanya deploy app dan menjalankan provisioning realm setelah infra **dan** app siap. Pisahkan secret infra dari workflow app; berikan hanya hak administrasi Keycloak yang diperlukan untuk provisioning.
- [ ] Sesuaikan backup/restore aplikasi untuk RustFS infra; pindahkan backup/restore Keycloak ke dokumentasi/operasi infra. Perbarui README dan contoh env kedua repo.

### 3. Latihan deployment

- [ ] Deploy infra baru pada lingkungan terisolasi; periksa PostgreSQL Keycloak, readiness Keycloak/RustFS, bucket, Caddy HTTPS, dan network bersama.
- [ ] Deploy app, worker, migrator, dan PostgreSQL aplikasi; pastikan proses deploy tidak memulai atau menghentikan service infra.
- [ ] Jalankan provisioning realm dari `btek-docs` **setelah kedua deployment berhasil**; verifikasi realm, client, role, redirect URI, web origin, dan secret. Jalankan ulang untuk membuktikan hasilnya tetap benar.
- [ ] Verifikasi login/callback/logout dengan akun uji baru, akses role, unggah/unduh lampiran baru, worker, serta akses S3 dan konsol sesuai kebijakan.
- [ ] Uji restart/release app tanpa menjatuhkan Keycloak/RustFS/Caddy; verifikasi prosedur backup/restore untuk data baru di kedua stack.

### 4. Deploy produksi dan penerimaan

- [ ] Deploy infra lebih dulu dan verifikasi Caddy, Keycloak, serta RustFS; cek hostname infra sso.bteklabs.com, storage.bteklabs.com, dan s3.bteklabs.com. Hostname app diverifikasi setelah btek-docs tersambung pada langkah berikutnya.
- [ ] Deploy `btek-docs` dengan endpoint infra, kemudian jalankan provisioning realm dari repo app.
- [ ] Buat akun uji baru dan verifikasi login, role, callback/logout, unggah/unduh file baru, worker, readiness, dan sertifikat HTTPS sebelum membuka akses pengguna.
- [ ] Amati log dan health kedua stack. Jika gate gagal, hentikan akses app, perbaiki konfigurasi/deployment, lalu ulangi provisioning yang aman dijalankan ulang. Karena tidak ada data Keycloak/RustFS lama yang dimigrasikan, rollback tidak memerlukan restore data lama.
- [ ] Setelah penerimaan, hapus definisi Keycloak/RustFS/Caddy lama serta secret yang tidak lagi dipakai dari deployment app. Jangan gunakan `docker compose down -v` untuk pembersihan.
- [ ] Centang item yang selesai dan catat bukti operasionalnya pada checklist ini.

## Gate selesai

Rilis `btek-docs` tidak mengubah siklus hidup service infra; Keycloak/RustFS berdiri sendiri; konfigurasi realm app berhasil di-push setelah kedua deployment; login dan upload baru berfungsi; dan backup untuk data yang mulai terbentuk setelah deployment tersedia.





