-- Misi Arsip Antariksa — bank soal yang dapat diedit dari panel pengajar
-- Jalankan sekali di Supabase → SQL Editor (setelah setup.sql).

create table if not exists public.maa_soal (
  id uuid primary key default gen_random_uuid(),
  planet int not null check (planet between 0 and 7),
  urutan int not null default 0,
  soal text not null,
  jawaban_benar text not null,
  pengecoh text[] not null,
  pembahasan text not null default '',
  petunjuk text not null default '',
  rujukan text not null default '',
  aktif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists maa_soal_planet_idx on public.maa_soal (planet, urutan);
alter table public.maa_soal enable row level security;
revoke all on public.maa_soal from anon, authenticated;

-- Dipanggil game: daftar soal aktif (soal latihan; kunci jawaban memang terlihat di browser)
create or replace function public.maa_ambil_soal()
returns table (id uuid, planet int, urutan int, soal text, jawaban_benar text, pengecoh text[], pembahasan text, petunjuk text, rujukan text)
language sql stable security definer set search_path = public as $$
  select id, planet, urutan, soal, jawaban_benar, pengecoh, pembahasan, petunjuk, rujukan
  from public.maa_soal where aktif order by planet, urutan, created_at;
$$;

-- Dipanggil panel pengajar: semua soal termasuk yang nonaktif
create or replace function public.maa_ambil_soal_pengajar(p_pin text)
returns setof public.maa_soal language plpgsql security definer set search_path = public as $$
begin
  if not public.maa_cek_pin(p_pin) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  return query select * from public.maa_soal order by planet, urutan, created_at;
end $$;

create or replace function public.maa_cek_minimal(p_planet int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.maa_soal where planet = p_planet and aktif) < 2 then
    raise exception 'Setiap planet harus memiliki minimal 2 soal aktif (game memilih 2 soal per planet).';
  end if;
end $$;
revoke all on function public.maa_cek_minimal(int) from public, anon, authenticated;

create or replace function public.maa_simpan_soal(p_pin text, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_old_planet int; v_planet int; v_peng text[];
begin
  if not public.maa_cek_pin(p_pin) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  v_planet := (p->>'planet')::int;
  if v_planet is null or v_planet not between 0 and 7 then raise exception 'Planet tidak valid'; end if;
  select array_agg(left(trim(x),400)) into v_peng from jsonb_array_elements_text(coalesce(p->'pengecoh','[]'::jsonb)) x;
  if coalesce(trim(p->>'soal'),'') = '' then raise exception 'Pertanyaan wajib diisi'; end if;
  if coalesce(trim(p->>'jawaban_benar'),'') = '' then raise exception 'Jawaban benar wajib diisi'; end if;
  if coalesce(array_length(v_peng,1),0) <> 3 or exists (select 1 from unnest(v_peng) e where e = '') then
    raise exception 'Isi tepat 3 pilihan jawaban salah (pengecoh)';
  end if;
  v_id := nullif(p->>'id','')::uuid;
  if v_id is not null then select planet into v_old_planet from public.maa_soal where id = v_id; end if;
  if v_id is null or v_old_planet is null then
    insert into public.maa_soal (planet, urutan, soal, jawaban_benar, pengecoh, pembahasan, petunjuk, rujukan, aktif)
    values (v_planet,
      coalesce((select max(urutan)+1 from public.maa_soal where planet = v_planet),1),
      left(trim(p->>'soal'),1000), left(trim(p->>'jawaban_benar'),400), v_peng,
      left(coalesce(trim(p->>'pembahasan'),''),2000), left(coalesce(trim(p->>'petunjuk'),''),600),
      left(coalesce(trim(p->>'rujukan'),''),200), coalesce((p->>'aktif')::boolean,true))
    returning id into v_id;
  else
    update public.maa_soal set
      planet = v_planet,
      urutan = case when v_planet <> v_old_planet then coalesce((select max(urutan)+1 from public.maa_soal where planet = v_planet),1) else urutan end,
      soal = left(trim(p->>'soal'),1000), jawaban_benar = left(trim(p->>'jawaban_benar'),400), pengecoh = v_peng,
      pembahasan = left(coalesce(trim(p->>'pembahasan'),''),2000), petunjuk = left(coalesce(trim(p->>'petunjuk'),''),600),
      rujukan = left(coalesce(trim(p->>'rujukan'),''),200), aktif = coalesce((p->>'aktif')::boolean,true), updated_at = now()
    where id = v_id;
    perform public.maa_cek_minimal(v_old_planet);
  end if;
  perform public.maa_cek_minimal(v_planet);
  return v_id;
end $$;

create or replace function public.maa_hapus_soal(p_pin text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_planet int;
begin
  if not public.maa_cek_pin(p_pin) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  delete from public.maa_soal where id = p_id returning planet into v_planet;
  if v_planet is not null then perform public.maa_cek_minimal(v_planet); end if;
end $$;

revoke all on function public.maa_ambil_soal() from public;
revoke all on function public.maa_ambil_soal_pengajar(text) from public;
revoke all on function public.maa_simpan_soal(text, jsonb) from public;
revoke all on function public.maa_hapus_soal(text, uuid) from public;
grant execute on function public.maa_ambil_soal() to anon, authenticated;
grant execute on function public.maa_ambil_soal_pengajar(text) to anon, authenticated;
grant execute on function public.maa_simpan_soal(text, jsonb) to anon, authenticated;
grant execute on function public.maa_hapus_soal(text, uuid) to anon, authenticated;

-- Isi awal: 32 soal bawaan game (hanya jika tabel masih kosong)
insert into public.maa_soal (planet, urutan, soal, jawaban_benar, pengecoh, pembahasan, petunjuk, rujukan) 
select * from (values
(0,1,$q$Manakah yang paling tepat menggambarkan arsip?$q$,$q$Rekaman kegiatan atau peristiwa dalam berbagai bentuk dan media.$q$,array[$q$Hanya surat kertas yang sudah berumur lebih dari 10 tahun.$q$,$q$Semua benda lama yang disimpan di gudang.$q$,$q$Hanya dokumen yang diberi stempel rahasia.$q$],$q$Arsip merupakan rekaman yang dibuat atau diterima dalam pelaksanaan kegiatan. Medianya bisa kertas, foto, rekaman suara, maupun elektronik.$q$,$q$Perhatikan hubungan dengan kegiatan dan keragaman medianya.$q$,$q$Pasal 1 angka 2$q$),
(0,2,$q$Rekaman digital rapat resmi dibuat dan diterima dalam kegiatan instansi. Apakah rekaman itu dapat menjadi arsip?$q$,$q$Ya, arsip dapat berbentuk rekaman elektronik.$q$,array[$q$Tidak, karena tidak dicetak di kertas.$q$,$q$Hanya jika sudah disimpan selama 30 tahun.$q$,$q$Tidak, karena arsip hanya berbentuk surat.$q$],$q$Definisi arsip mencakup berbagai bentuk dan media sesuai perkembangan teknologi, termasuk rekaman digital kegiatan.$q$,$q$Arsip tidak dibatasi pada media kertas.$q$,$q$Pasal 1 angka 2$q$),
(0,3,$q$Istilah “kearsipan” mengacu pada apa?$q$,$q$Hal-hal yang berkenaan dengan arsip.$q$,array[$q$Kegiatan mengirim surat saja.$q$,$q$Penjualan dokumen yang tidak terpakai.$q$,$q$Pekerjaan merawat gedung kantor saja.$q$],$q$Kearsipan mencakup hal-hal yang berkenaan dengan arsip, bukan hanya penyimpanan atau pengiriman surat.$q$,$q$Pilih pengertian yang mencakup keseluruhan urusan arsip.$q$,$q$Pasal 1 angka 1$q$),
(0,4,$q$Apa yang menjadi ciri seorang arsiparis menurut UU Kearsipan?$q$,$q$Memiliki kompetensi kearsipan serta fungsi, tugas, dan tanggung jawab melaksanakan kegiatan kearsipan.$q$,array[$q$Setiap orang yang pernah menyimpan sebuah surat.$q$,$q$Hanya orang yang mengelola buku perpustakaan.$q$,$q$Semua pegawai yang bekerja di gedung tua.$q$],$q$Kompetensi arsiparis diperoleh melalui pendidikan formal dan/atau pendidikan dan pelatihan kearsipan, disertai tanggung jawab dalam kegiatan kearsipan.$q$,$q$Perhatikan kompetensi dan tanggung jawab profesinya.$q$,$q$Pasal 1 angka 10$q$),
(1,1,$q$Berkas layanan digunakan hampir setiap hari. Berdasarkan frekuensi penggunaannya, berkas itu termasuk…$q$,$q$Arsip aktif.$q$,array[$q$Arsip inaktif.$q$,$q$Arsip statis secara otomatis.$q$,$q$Arsip yang wajib segera dimusnahkan.$q$],$q$Arsip aktif ditandai oleh frekuensi penggunaan yang tinggi dan/atau terus-menerus.$q$,$q$Kuncinya adalah seberapa sering arsip digunakan.$q$,$q$Pasal 1 angka 5$q$),
(1,2,$q$Frekuensi penggunaan berkas telah menurun. Berkas tersebut termasuk…$q$,$q$Arsip inaktif.$q$,array[$q$Arsip aktif.$q$,$q$Arsip yang bukan milik instansi lagi.$q$,$q$Arsip yang otomatis tidak bernilai guna.$q$],$q$Frekuensi penggunaan yang menurun menunjukkan arsip inaktif. Penurunan penggunaan tidak otomatis membolehkan pemusnahan.$q$,$q$Jarang digunakan tidak sama dengan boleh dibuang.$q$,$q$Pasal 1 angka 6$q$),
(1,3,$q$Apa ciri utama arsip dinamis?$q$,$q$Digunakan langsung dalam kegiatan pencipta arsip dan disimpan untuk jangka waktu tertentu.$q$,array[$q$Selalu disimpan selamanya di museum.$q$,$q$Hanya berbentuk video yang bergerak.$q$,$q$Tidak pernah dipakai dalam pekerjaan.$q$],$q$Kata dinamis merujuk pada penggunaannya dalam kegiatan pencipta arsip, bukan gerakan gambar atau jenis medianya.$q$,$q$Hubungkan istilah dinamis dengan kegiatan organisasi.$q$,$q$Pasal 1 angka 3$q$),
(1,4,$q$Siapa yang bertanggung jawab atas pengelolaan arsip dinamis?$q$,$q$Pencipta arsip.$q$,array[$q$Pengunjung museum.$q$,$q$Pembeli kertas bekas.$q$,$q$Semua pengikut akun media sosial instansi.$q$],$q$Pengelolaan arsip dinamis menjadi tanggung jawab pencipta arsip; pengelolaan arsip statis menjadi tanggung jawab lembaga kearsipan.$q$,$q$Pilih pihak yang menjalankan kegiatan dan memiliki arsip dinamis.$q$,$q$Pasal 9 ayat (3)–(4)$q$),
(2,1,$q$Apa rangkaian utama pengelolaan arsip dinamis?$q$,$q$Penciptaan; penggunaan dan pemeliharaan; penyusutan.$q$,array[$q$Penciptaan; penjualan; pembuangan bebas.$q$,$q$Pemindaian; penghapusan semua naskah asli.$q$,$q$Penyimpanan tanpa pencatatan dan tanpa batas waktu.$q$],$q$Pengelolaan arsip dinamis meliputi penciptaan, penggunaan dan pemeliharaan, serta penyusutan sesuai ketentuan.$q$,$q$Pengelolaan mencakup sejak arsip tercipta sampai penyusutannya.$q$,$q$Pasal 40 ayat (2)$q$),
(2,2,$q$Penciptaan arsip harus memenuhi tiga komponen. Apa saja?$q$,$q$Struktur, isi, dan konteks.$q$,array[$q$Warna, harga, dan ukuran rak.$q$,$q$Nama aplikasi, kata sandi, dan jaringan.$q$,$q$Lama rapat, jumlah kursi, dan ruang kantor.$q$],$q$Struktur, isi, dan konteks membantu menjelaskan bentuk, informasi, serta lingkungan penciptaan arsip.$q$,$q$Komponen tersebut menjelaskan bentuk, informasi, dan latar penciptaannya.$q$,$q$Pasal 41 ayat (3)$q$),
(2,3,$q$Manakah perangkat yang mendukung pengelolaan arsip dinamis secara efektif?$q$,$q$Tata naskah dinas, klasifikasi arsip, JRA, serta sistem klasifikasi keamanan dan akses arsip.$q$,array[$q$Daftar warna folder dan daftar belanja kantor saja.$q$,$q$Daftar hadir pegawai tanpa instrumen kearsipan.$q$,$q$Satu kata sandi bersama untuk semua dokumen.$q$],$q$Empat instrumen ini membantu penciptaan, pengelompokan, retensi, serta pengaturan keamanan dan akses arsip.$q$,$q$Pilih paket yang mengatur naskah, klasifikasi, retensi, dan akses.$q$,$q$Pasal 40 ayat (4)$q$),
(2,4,$q$Mengapa arsip dinamis perlu dipelihara?$q$,$q$Untuk menjaga keamanan informasi dan fisik arsip.$q$,array[$q$Agar semua arsip dapat dibuka siapa saja.$q$,$q$Agar arsip bisa diubah tanpa jejak.$q$,$q$Agar arsip tidak perlu ditemukan kembali.$q$],$q$Pemeliharaan arsip dinamis dilakukan oleh pencipta arsip untuk menjamin keamanan informasi sekaligus fisiknya.$q$,$q$Keamanan harus mencakup isi maupun media arsip.$q$,$q$Pasal 45 ayat (1)$q$),
(3,1,$q$Apa fungsi Jadwal Retensi Arsip (JRA)?$q$,$q$Menjadi pedoman penyusutan dan penyelamatan arsip melalui informasi retensi, jenis arsip, dan rekomendasi akhirnya.$q$,array[$q$Menentukan jam masuk dan pulang pegawai.$q$,$q$Menentukan harga jual seluruh dokumen.$q$,$q$Mengganti semua aturan akses arsip.$q$],$q$JRA memuat sekurang-kurangnya retensi, jenis arsip, serta rekomendasi musnah, dinilai kembali, atau permanen.$q$,$q$Retensi berkaitan dengan jangka waktu penyimpanan.$q$,$q$Pasal 1 angka 22$q$),
(3,2,$q$Dalam penyusutan, arsip inaktif dipindahkan dari mana ke mana?$q$,$q$Dari unit pengolah ke unit kearsipan.$q$,array[$q$Dari unit kearsipan ke toko kertas bekas.$q$,$q$Dari lembaga kearsipan ke semua pengunjung.$q$,$q$Dari kantor ke rumah pribadi tanpa pencatatan.$q$],$q$Pemindahan arsip inaktif dari unit pengolah ke unit kearsipan merupakan salah satu bentuk penyusutan arsip.$q$,$q$Pemindahan tetap berada dalam tata kelola pencipta arsip.$q$,$q$Pasal 49 huruf a$q$),
(3,3,$q$Manakah tiga bentuk penyusutan arsip?$q$,$q$Pemindahan arsip inaktif, pemusnahan sesuai ketentuan, dan penyerahan arsip statis.$q$,array[$q$Pemindaian, fotokopi, dan pencetakan.$q$,$q$Penggantian nama folder, pewarnaan, dan penjilidan.$q$,$q$Pengumpulan, penjualan, dan pembuangan sembarang.$q$],$q$Penyusutan bukan sekadar membuang arsip. Kegiatannya meliputi pemindahan, pemusnahan yang sah, serta penyerahan arsip statis.$q$,$q$Ada tindakan untuk arsip inaktif, arsip yang boleh musnah, dan arsip statis.$q$,$q$Pasal 49 huruf a–c$q$),
(3,4,$q$Apakah kementerian sebagai lembaga negara wajib memiliki JRA?$q$,$q$Ya, lembaga negara wajib memiliki JRA.$q$,array[$q$Tidak, JRA hanya untuk museum.$q$,$q$Hanya jika semua arsip berbentuk kertas.$q$,$q$Tidak, retensi boleh ditentukan setiap pegawai sendiri.$q$],$q$Kewajiban memiliki JRA berlaku bagi lembaga negara, pemerintahan daerah, perguruan tinggi negeri, BUMN dan/atau BUMD.$q$,$q$JRA adalah instrumen wajib bagi lembaga negara.$q$,$q$Pasal 48 ayat (1)$q$),
(4,1,$q$Retensi arsip sudah habis, tetapi arsip masih berkaitan dengan penyelesaian suatu perkara. Apa tindakan yang tepat?$q$,$q$Tidak memusnahkannya karena masih terkait penyelesaian perkara.$q$,array[$q$Segera membakarnya agar ruang penyimpanan lega.$q$,$q$Menghapusnya karena retensi adalah satu-satunya syarat.$q$,$q$Menjualnya tanpa memeriksa ketentuan lain.$q$],$q$Salah satu syarat pemusnahan adalah arsip tidak berkaitan dengan penyelesaian proses suatu perkara. Habis retensi saja belum cukup.$q$,$q$Perhatikan status perkara, bukan hanya umur arsip.$q$,$q$Pasal 51 ayat (1) huruf d$q$),
(4,2,$q$Pilih kondisi yang memenuhi seluruh syarat materiil pemusnahan arsip.$q$,$q$Tidak bernilai guna; retensi habis dan berketerangan musnah menurut JRA; tidak dilarang aturan; tidak terkait penyelesaian perkara.$q$,array[$q$Sudah lama, berdebu, dan memenuhi lemari.$q$,$q$Sudah dipindai, tanpa pemeriksaan syarat lain.$q$,$q$Pemilik ruangan meminta seluruh berkas dibuang.$q$],$q$Keempat syarat harus diperhatikan bersama. Pemusnahan juga tetap wajib mengikuti prosedur yang benar.$q$,$q$Pilih jawaban yang memeriksa nilai guna, JRA, larangan, dan perkara.$q$,$q$Pasal 51 ayat (1)–(2)$q$),
(4,3,$q$Siapa yang bertanggung jawab atas pemusnahan arsip pada pencipta arsip?$q$,$q$Pimpinan pencipta arsip yang bersangkutan.$q$,array[$q$Petugas kebersihan atas keputusan sendiri.$q$,$q$Pihak yang membeli kertas bekas.$q$,$q$Pengunjung kantor yang membutuhkan ruang.$q$],$q$Pemusnahan arsip pada pencipta arsip merupakan tanggung jawab pimpinan pencipta arsip dan harus mengikuti prosedur yang benar.$q$,$q$Keputusan ini merupakan tanggung jawab organisasi.$q$,$q$Pasal 51 ayat (2)–(3)$q$),
(4,4,$q$Berkas telah dipindai. Apakah naskah aslinya otomatis boleh dimusnahkan?$q$,$q$Tidak; syarat dan prosedur pemusnahan tetap harus dipenuhi.$q$,array[$q$Ya, setiap hasil pindai otomatis mengizinkan pemusnahan.$q$,$q$Ya, selama hasil pindai bisa dibuka di ponsel.$q$,$q$Ya, jika folder digital diberi nama yang rapi.$q$],$q$Pemindaian bukan pengganti penilaian nilai guna, pemeriksaan JRA, larangan hukum, status perkara, dan prosedur pemusnahan.$q$,$q$Digitalisasi tidak menghapus kewajiban pemeriksaan pemusnahan.$q$,$q$Pasal 51 ayat (1)–(2)$q$),
(5,1,$q$Apa yang membedakan arsip vital?$q$,$q$Menjadi syarat dasar kelangsungan operasional, tidak dapat diperbarui, dan tidak tergantikan jika rusak atau hilang.$q$,array[$q$Semua arsip yang berwarna merah.$q$,$q$Hanya arsip yang dicetak pada kertas mahal.$q$,$q$Arsip yang boleh diganti dengan cerita lisan.$q$],$q$Arsip vital sangat penting bagi kelangsungan operasional pencipta arsip dan tidak tergantikan apabila rusak atau hilang.$q$,$q$Fokus pada kelangsungan operasional dan sifat tidak tergantikan.$q$,$q$Pasal 1 angka 4$q$),
(5,2,$q$Arsip terjaga berkaitan dengan apa?$q$,$q$Keberadaan dan kelangsungan hidup bangsa dan negara.$q$,array[$q$Semua dokumen yang kebetulan berada di lemari terkunci.$q$,$q$Hanya catatan belanja pribadi pegawai.$q$,$q$Semua kertas yang belum diberi nomor.$q$],$q$Arsip terjaga adalah arsip negara yang berkaitan dengan keberadaan dan kelangsungan hidup bangsa dan negara; keutuhan, keamanan, dan keselamatannya harus dijaga.$q$,$q$Kategori ini ditentukan oleh kepentingannya bagi bangsa dan negara.$q$,$q$Pasal 1 angka 8$q$),
(5,3,$q$Menurut Pasal 43 ayat (2), kapan pemberkasan dan pelaporan arsip kegiatan strategis yang dimaksud pada ayat (1) wajib dilakukan?$q$,$q$Paling lama 1 tahun sejak terjadinya kegiatan.$q$,array[$q$Paling lama 10 tahun setelah pegawai pensiun.$q$,$q$Hanya setelah arsip diminta wartawan.$q$,$q$Tidak ada batas waktu sama sekali.$q$],$q$Pemberkasan dan pelaporan kepada ANRI dilakukan paling lama satu tahun sejak kegiatan. Ini berbeda dari tenggat penyerahan salinan autentik pada ayat (3).$q$,$q$Tenggat dihitung sejak terjadinya kegiatan.$q$,$q$Pasal 43 ayat (1)–(2)$q$),
(5,4,$q$Apa saja kegiatan dalam program arsip vital?$q$,$q$Identifikasi; pelindungan dan pengamanan; penyelamatan dan pemulihan.$q$,array[$q$Pewarnaan; penjualan; pembuangan.$q$,$q$Penghapusan; penggantian; pengabaian.$q$,$q$Peminjaman bebas tanpa pencatatan.$q$],$q$Program arsip vital dimulai dengan identifikasi, dilanjutkan pelindungan dan pengamanan, serta penyelamatan dan pemulihan.$q$,$q$Program ini menyiapkan pencegahan sekaligus penanganan gangguan.$q$,$q$Pasal 56 ayat (2)$q$),
(6,1,$q$Kepada siapa pencipta arsip wajib menyediakan arsip dinamis?$q$,$q$Pengguna arsip yang berhak.$q$,array[$q$Siapa pun tanpa memeriksa hak akses.$q$,$q$Hanya orang yang membayar secara pribadi.$q$,$q$Tidak kepada siapa pun, tanpa pengecualian.$q$],$q$Pencipta arsip wajib menyediakan arsip dinamis bagi pengguna yang berhak. Hak akses dan ketentuan kerahasiaan tetap diperhatikan.$q$,$q$Akses harus memperhatikan kewenangan pengguna.$q$,$q$Pasal 42 ayat (1)$q$),
(6,2,$q$Pembukaan arsip kepada umum dapat mengungkap rahasia atau data pribadi. Apa yang dimungkinkan UU?$q$,$q$Pencipta arsip dapat menutup akses dengan alasan tersebut dan wajib menjaga kerahasiaan arsip tertutup.$q$,array[$q$Semua data pribadi harus diumumkan tanpa pengecualian.$q$,$q$Arsip harus langsung dimusnahkan.$q$,$q$Data boleh dijual kepada pihak yang menawarkan harga tertinggi.$q$],$q$UU mengatur alasan penutupan akses, termasuk pengungkapan rahasia atau data pribadi. Arsip tertutup wajib dijaga kerahasiaannya.$q$,$q$Perlindungan informasi berbeda dari pemusnahan arsip.$q$,$q$Pasal 44 ayat (1) huruf h dan ayat (2)$q$),
(6,3,$q$Apa kewajiban pengelola arsip dinamis terhadap arsip yang dikelolanya?$q$,$q$Menjaga keautentikan, keutuhan, keamanan, dan keselamatannya.$q$,array[$q$Mengubah isi arsip agar tampak lebih menguntungkan.$q$,$q$Membagikan seluruh arsip ke akun pribadi.$q$,$q$Menghilangkan bagian yang dianggap merepotkan.$q$],$q$Arsip harus tetap autentik dan utuh serta terlindungi keamanan dan keselamatannya agar dapat dipercaya.$q$,$q$Pertahankan keaslian serta kelengkapan arsip.$q$,$q$Pasal 40 ayat (5)$q$),
(6,4,$q$Bagaimana akses arsip statis dilaksanakan?$q$,$q$Memperhatikan keutuhan, keamanan, keselamatan, serta ketentuan keterbukaan dan ketertutupan.$q$,array[$q$Membuka seluruh arsip tanpa mempertimbangkan ketentuan apa pun.$q$,$q$Melarang seluruh pengguna selamanya.$q$,$q$Mengubah isi arsip sebelum diberikan kepada pengguna.$q$],$q$Kemudahan akses arsip statis dijamin dengan tetap memperhatikan pelindungan arsip dan aturan keterbukaan atau ketertutupan.$q$,$q$Layanan akses berjalan bersama perlindungan arsip.$q$,$q$Pasal 64 ayat (1)–(3)$q$),
(7,1,$q$Kondisi mana yang sesuai dengan definisi arsip statis?$q$,$q$Bernilai guna kesejarahan, retensi habis, berketerangan permanen, dan telah diverifikasi ANRI dan/atau lembaga kearsipan.$q$,array[$q$Semua arsip yang tidak dipindahkan dari meja.$q$,$q$Semua arsip yang berumur satu tahun.$q$,$q$Semua arsip yang jarang dibaca tanpa penilaian lain.$q$],$q$Status arsip statis ditentukan oleh nilai kesejarahan, retensi, keterangan permanen, dan verifikasi; bukan semata-mata usia arsip.$q$,$q$Usia arsip saja tidak menentukan status statis.$q$,$q$Pasal 1 angka 7$q$),
(7,2,$q$Apa rangkaian pengelolaan arsip statis menurut Pasal 59 ayat (2)?$q$,$q$Akuisisi, pengolahan, preservasi, dan akses.$q$,array[$q$Penciptaan, penjualan, pembuangan, dan penggantian.$q$,$q$Pembelian rak dan pengecatan ruangan saja.$q$,$q$Pemindaian lalu pemusnahan seluruh naskah.$q$],$q$Arsip statis dikelola melalui akuisisi, pengolahan, preservasi, dan akses agar dapat diselamatkan dan dimanfaatkan.$q$,$q$Rangkaian ini mencakup penerimaan, penataan, pelestarian, dan pemanfaatan.$q$,$q$Pasal 59 ayat (2)$q$),
(7,3,$q$Apa tujuan preservasi arsip statis?$q$,$q$Menjamin keselamatan dan kelestarian arsip statis.$q$,array[$q$Membuat semua arsip menjadi rahasia permanen.$q$,$q$Mengganti informasi sejarah agar lebih menarik.$q$,$q$Menghilangkan seluruh identitas penciptanya.$q$],$q$Preservasi menjaga keselamatan dan kelestarian arsip statis melalui tindakan preventif dan kuratif.$q$,$q$Preservasi berkaitan dengan pelestarian.$q$,$q$Pasal 63 ayat (1)–(2)$q$),
(7,4,$q$Mengapa arsip autentik dan terpercaya penting bagi penyelenggaraan kearsipan?$q$,$q$Agar tersedia sebagai alat bukti yang sah.$q$,array[$q$Agar setiap orang dapat mengubah bukti kegiatan.$q$,$q$Agar organisasi tidak perlu mempertanggungjawabkan kegiatan.$q$,$q$Agar semua dokumen dapat dijual bebas.$q$],$q$Salah satu tujuan penyelenggaraan kearsipan adalah menjamin ketersediaan arsip autentik dan terpercaya sebagai alat bukti yang sah.$q$,$q$Hubungkan arsip dengan pembuktian dan pertanggungjawaban.$q$,$q$Pasal 3 huruf b$q$)
) v where not exists (select 1 from public.maa_soal);
