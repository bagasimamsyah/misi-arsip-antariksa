# Misi Arsip Antariksa

Game penerbangan 2D untuk pembelajaran kearsipan. Pemain menerbangkan ARKA–01 melewati delapan planet, mengambil kapsul arsip, dan menjawab dua soal pada setiap checkpoint untuk melanjutkan misi.

## Alamat

| Halaman | Untuk | Alamat |
| --- | --- | --- |
| Game | Peserta | `https://<domain-vercel>/` |
| Game dengan kode kelas otomatis | Peserta | `https://<domain-vercel>/?kelas=ARS-01` |
| Panel pengajar | Pengajar (butuh PIN) | `https://<domain-vercel>/pengajar` |

## Hasil peserta ke pengajar (Supabase)

- Peserta wajib mengisi **nama**, dan sebaiknya **kode kelas** (bisa terisi otomatis lewat tautan `?kelas=...`).
- Game mengirim progres ke Supabase saat misi dimulai, setiap checkpoint selesai, dan saat misi tuntas. Jika internet putus, kiriman disimpan di browser dan dikirim ulang pada checkpoint berikutnya; di layar akhir ada tombol **Kirim ulang**.
- Panel pengajar (`/pengajar`) menampilkan: ringkasan kelas, peringkat peserta, progres 8 planet, detail jawaban tiap peserta (termasuk pilihan salah), **analisis soal** (soal tersulit dan jawaban salah terbanyak), unduh **CSV untuk Excel**, hapus data uji coba, dan ganti PIN. Data diperbarui otomatis tiap 15 detik.
- Keamanan: tabel tidak bisa dibaca langsung dari browser. Peserta hanya dapat mengirim hasil melalui fungsi `maa_kirim_hasil`; membaca/menghapus data memerlukan PIN pengajar (disimpan sebagai hash bcrypt).
- Struktur database ada di `supabase/setup.sql` (tabel berawalan `maa_`). Untuk proyek Supabase baru: jalankan file itu di SQL Editor (ganti `GANTI_PIN_INI`), lalu ganti `SUPABASE_URL` dan `SUPABASE_KEY` di `index.html` dan `pengajar.html`.
- **Kelola soal tanpa koding:** di panel pengajar, buka menu **Kelola soal**. Pengajar dapat menambah, mengubah, menonaktifkan, memindahkan planet, atau menghapus soal beserta jawaban benar, 3 pengecoh, pembahasan, petunjuk, dan rujukan pasal. Soal disimpan di tabel `maa_soal` (lihat `supabase/soal.sql`). Game mengambil soal terbaru setiap kali dibuka; jika Supabase tidak terjangkau, game memakai salinan terakhir atau soal bawaan di `index.html`. Setiap planet wajib memiliki minimal 2 soal aktif.
- Lupa PIN? Jalankan di Supabase SQL Editor:
  `update public.maa_pengaturan set pin_hash = extensions.crypt('PIN_BARU', extensions.gen_salt('bf')) where id = 1;`

## Coba di komputer

1. Ekstrak file ZIP.
2. Buka `index.html` dengan Chrome, Edge, Firefox, atau Safari yang mendukung Canvas dan elemen `dialog`.
3. Isi nama pilot bila ingin, pilih mode, lalu klik **Mulai misi**.

Seluruh CSS, JavaScript, soal, dan visual berada di dalam `index.html`. Tidak perlu Node.js atau npm. Game tetap bisa dimainkan tanpa internet, tetapi hasil baru terkirim ke pengajar bila ada koneksi. Tautan sumber hukum membutuhkan internet. Fitur penyimpanan pada alamat `file://` dapat dibatasi oleh browser; gunakan versi yang dihosting untuk penyimpanan yang lebih konsisten.

## Unggah ke GitHub

1. Masuk ke akun GitHub, buat repositori baru, misalnya `misi-arsip-antariksa`.
2. Di repositori kosong, pilih **uploading an existing file** atau **Add file → Upload files**.
3. Unggah **isi folder hasil ekstrak**, terutama `index.html`, `vercel.json`, dan `README.md`.
4. Pastikan `index.html` dan `vercel.json` berada di tingkat teratas repositori, bukan di dalam ZIP atau subfolder tambahan.
5. Klik **Commit changes**.

File `.gitignore` boleh ikut disertakan ketika menggunakan Git dari komputer. File tersembunyi ini tidak diperlukan untuk menjalankan game.

Alternatif melalui terminal, jalankan dari folder proyek yang telah diekstrak:

```bash
git init
git add .
git commit -m "Tambahkan game Misi Arsip Antariksa"
git branch -M main
git remote add origin https://github.com/USERNAME/misi-arsip-antariksa.git
git push -u origin main
```

Ganti `USERNAME` dan nama repositori dengan milik Anda. Repositori tujuan harus sudah dibuat.

## Deploy melalui Vercel

1. Masuk ke Vercel menggunakan akun Anda.
2. Pilih **Add New → Project**, lalu hubungkan GitHub bila diperlukan.
3. Pilih dan **Import** repositori game.
4. Gunakan pengaturan berikut. File `vercel.json` telah menyediakannya.

| Pengaturan | Nilai |
| --- | --- |
| Framework Preset | `Other` |
| Root Directory | Folder repositori yang memuat `index.html` |
| Build Command | Kosong; aktifkan Override bila perlu |
| Install Command | Kosong |
| Output Directory | `.` |
| Environment Variables | Tidak diperlukan (alamat & kunci publik Supabase ada di file HTML) |

5. Klik **Deploy**.
6. Setelah berhasil, buka alamat situs yang diberikan Vercel dan coba **Mulai misi**.

Untuk memperbarui permainan, ubah `index.html` di GitHub dan commit perubahan. Integrasi Git Vercel dapat menerbitkan ulang perubahan dari cabang yang dihubungkan. Periksa pengaturan deployment proyek Anda.

**Jika muncul 404:** periksa bahwa file bernama tepat `index.html`, bukan `index.html.txt`, dan Root Directory mengarah ke folder yang memuatnya. ZIP harus diekstrak sebelum diunggah.

**Jika Vercel meminta perintah build:** pilih `Other` dan kosongkan Build Command. Proyek ini adalah situs statis tanpa langkah build.

## Cara bermain

| Kontrol | Fungsi |
| --- | --- |
| Panah / WASD | Menggerakkan pesawat ke empat arah |
| Geser di area antariksa | Mengarahkan pesawat pada layar sentuh atau dengan mouse |
| Tombol arah di layar | Kontrol alternatif pada perangkat sentuh |
| P / Escape | Jeda penerbangan |
| M | Mengaktifkan atau mematikan efek suara |
| Enter | Masuk checkpoint ketika pesawat sudah dekat |
| Tombol 1–4 | Memilih jawaban kuis |

- Pesawat melaju otomatis. Ambil kapsul hijau dan hindari asteroid.
- Setelah sekitar 22 detik penerbangan aktif per planet, cincin checkpoint muncul. Arahkan pesawat ke dalam cincin. Tombol **Masuk checkpoint** tersedia ketika sudah dekat.
- Gerbang tidak terlewati secara otomatis. Pemain harus menyelesaikan **dua soal dengan benar**.
- Jika jawaban salah, baca petunjuk lalu pilih lagi. Tidak ada batas waktu menjawab.
- Mode **Jelajah** memiliki tiga perisai. Jika habis, pemain mengulang penerbangan planet yang sama. Poin dan kapsul dari penerbangan yang gagal dikembalikan ke kondisi awal planet tersebut.
- Mode **Santai** menghilangkan kerusakan akibat asteroid. Soal dan syarat membuka gerbang tetap sama.
- Selesaikan delapan planet untuk melihat ringkasan, pembahasan seluruh soal yang dikerjakan, dan tombol **Unduh hasil (.txt)**.

## Skor dan progres

| Peristiwa | Poin / efek |
| --- | --- |
| Kapsul arsip | +10 poin |
| Benar pada percobaan pertama | +100 poin |
| Benar pada percobaan kedua | +70 poin |
| Benar pada percobaan ketiga | +40 poin |
| Benar pada percobaan keempat | +25 poin |
| Checkpoint selesai | +50 poin; pulihkan 1 perisai, maksimal 3 |

Rekor mode Jelajah dan Santai terpisah. Progres disimpan setelah checkpoint selesai melalui `localStorage`, hanya pada browser dan alamat situs tersebut. Muat ulang atau tutup tab berarti mengulang penerbangan setelah checkpoint terakhir yang selesai. Memulai misi baru mengganti simpanan sebelumnya. Riwayat permainan tidak disinkronkan antarperangkat. Browser privat atau pengaturan penyimpanan yang ketat dapat membatasi fitur ini.

Nama, kode kelas, skor, progres, dan riwayat jawaban dikirim ke database Supabase agar dapat dilihat pengajar. Rekor pribadi tetap disimpan di browser. Halaman yang dihosting tetap tunduk pada layanan hosting yang Anda gunakan. Hasil merupakan bahan refleksi belajar, bukan sertifikat kompetensi. Karena semua kode dan kunci jawaban berada di sisi browser, game ini ditujukan untuk latihan, bukan ujian dengan pengawasan atau penilaian berisiko tinggi.

## Rute dan materi

| Planet | Tema | Acuan utama UU 43/2009 |
| --- | --- | --- |
| Merkurius | Mengenal arsip | Pasal 1 |
| Venus | Arsip dinamis | Pasal 1 dan 9 |
| Bumi | Siklus pengelolaan | Pasal 40, 41, 45 |
| Mars | Retensi dan penyusutan | Pasal 1, 48, 49 |
| Jupiter | Pemusnahan yang benar | Pasal 51 |
| Saturnus | Arsip vital dan terjaga | Pasal 1, 43, 56 |
| Uranus | Akses dan keamanan | Pasal 40, 42, 44, 64 |
| Neptunus | Memori bangsa dan arsip statis | Pasal 1, 3, 59, 63 |

Tersedia **32 soal**: empat soal per planet. Setiap misi memilih dua soal per planet dan mengacak urutan pilihan jawaban. Total soal yang dikerjakan adalah 16. Pembahasan mencantumkan rujukan pasal.

Sumber resmi, diperiksa pada 20 Oktober 2026:

- [UU No. 43 Tahun 2009 tentang Kearsipan — JDIH ANRI](https://jdih.anri.go.id/peraturan/undang-undang-no-43-tahun-2009)
- [Naskah UU No. 43 Tahun 2009 — PDF JDIH ANRI](https://jdih.anri.go.id/storage/rules/January2024/F2YRiGn9owRllGoS7EHZ.pdf)
- [Pengaturan build dan situs statis — dokumentasi Vercel](https://vercel.com/docs/builds/configure-a-build)

Desain ini tidak menyatakan afiliasi resmi dengan ANRI. Planet dan jaraknya digambarkan secara artistik, bukan sebagai simulasi astronomi berskala.

## Mengubah game

Buka `index.html` dengan editor teks, misalnya Visual Studio Code.

- **Soal:** sebaiknya lewat menu **Kelola soal** di `/pengajar`. Soal di `const BANK =` hanya cadangan bila database tidak terjangkau. Tiap soal menggunakan `q` (pertanyaan), `a` (empat jawaban), `why` (pembahasan), `hint` (petunjuk), dan `ref` (rujukan pasal). **Letakkan jawaban benar di indeks pertama `a`.** Game mengacak tampilannya saat dimainkan. Pertahankan delapan kelompok planet dan sedikitnya dua soal per kelompok.
- **Planet:** cari `const PLANETS =` untuk nama, tema, dan warna.
- **Durasi penerbangan:** cari `const FLIGHT_SECONDS = 22` dan ubah angkanya dalam detik.
- **Teks beranda:** cari `Jelajahi semesta.` dan `Lindungi ingatan.`.
- **Warna tampilan:** variabel warna berada pada bagian `:root` di awal `<style>`.

Setelah mengubah struktur bank soal atau perhitungan skor secara besar, ganti akhiran versi pada konstanta `STORE` dan `BEST` agar simpanan lama tidak bercampur dengan format baru. Jumlah dua soal dan delapan planet digunakan pada beberapa teks dan perhitungan; jangan mengubah jumlahnya tanpa menyesuaikan alur terkait.

Semua visual dibuat dengan Canvas dan SVG sebaris, serta efek suara dengan Web Audio. Tidak ada font eksternal, library JavaScript, atau aset CDN. Satu-satunya permintaan jaringan adalah pengiriman hasil ke Supabase.
