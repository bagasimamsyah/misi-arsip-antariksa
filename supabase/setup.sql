-- Misi Arsip Antariksa — struktur database Supabase
-- Jalankan sekali di Supabase → SQL Editor. Ganti PIN awal di baris insert bila perlu.

create table if not exists public.maa_hasil (
  id uuid primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  nama text not null,
  kelas text not null default '',
  mode text not null default 'explore',
  status text not null default 'bermain',
  planet int not null default 0,
  skor int not null default 0,
  benar_pertama int not null default 0,
  dijawab int not null default 0,
  salah int not null default 0,
  kapsul int not null default 0,
  waktu_aktif int not null default 0,
  riwayat jsonb not null default '[]'::jsonb
);
create index if not exists maa_hasil_kelas_idx on public.maa_hasil (kelas, updated_at desc);
alter table public.maa_hasil enable row level security;

create table if not exists public.maa_pengaturan (
  id int primary key default 1 check (id = 1),
  pin_hash text not null
);
alter table public.maa_pengaturan enable row level security;
insert into public.maa_pengaturan (id, pin_hash)
values (1, extensions.crypt('GANTI_PIN_INI', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- Tabel tidak bisa dibaca/ditulis langsung dari browser; semua lewat fungsi di bawah.
revoke all on public.maa_hasil from anon, authenticated;
revoke all on public.maa_pengaturan from anon, authenticated;

-- Dipanggil game peserta: simpan / perbarui hasil satu sesi permainan
create or replace function public.maa_kirim_hasil(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := (p->>'id')::uuid;
  if v_id is null then raise exception 'id wajib'; end if;
  if jsonb_typeof(coalesce(p->'riwayat','[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p->'riwayat','[]'::jsonb)) > 40 then
    raise exception 'riwayat tidak valid';
  end if;
  insert into public.maa_hasil as h (id, nama, kelas, mode, status, planet, skor, benar_pertama, dijawab, salah, kapsul, waktu_aktif, riwayat)
  values (
    v_id,
    left(coalesce(nullif(trim(p->>'nama'),''),'Tanpa nama'),60),
    upper(left(coalesce(trim(p->>'kelas'),''),40)),
    case when p->>'mode' = 'relaxed' then 'relaxed' else 'explore' end,
    case when p->>'status' = 'selesai' then 'selesai' else 'bermain' end,
    least(greatest(coalesce((p->>'planet')::int,0),0),8),
    least(greatest(coalesce((p->>'skor')::int,0),0),100000),
    least(greatest(coalesce((p->>'benar_pertama')::int,0),0),16),
    least(greatest(coalesce((p->>'dijawab')::int,0),0),16),
    least(greatest(coalesce((p->>'salah')::int,0),0),1000),
    least(greatest(coalesce((p->>'kapsul')::int,0),0),100000),
    least(greatest(coalesce((p->>'waktu_aktif')::int,0),0),864000),
    coalesce(p->'riwayat','[]'::jsonb)
  )
  on conflict (id) do update set
    nama = excluded.nama, kelas = excluded.kelas, mode = excluded.mode,
    status = case when h.status = 'selesai' then 'selesai' else excluded.status end,
    planet = greatest(h.planet, excluded.planet),
    skor = excluded.skor, benar_pertama = excluded.benar_pertama, dijawab = excluded.dijawab,
    salah = excluded.salah, kapsul = excluded.kapsul, waktu_aktif = excluded.waktu_aktif,
    riwayat = excluded.riwayat, updated_at = now()
  where h.status <> 'selesai' or excluded.status = 'selesai';
end $$;

create or replace function public.maa_cek_pin(p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare ok boolean;
begin
  select pin_hash = extensions.crypt(coalesce(p_pin,''), pin_hash) into ok from public.maa_pengaturan where id = 1;
  if not coalesce(ok,false) then perform pg_sleep(1); end if;
  return coalesce(ok,false);
end $$;
revoke all on function public.maa_cek_pin(text) from public, anon, authenticated;

-- Dipanggil halaman pengajar (butuh PIN)
create or replace function public.maa_ambil_hasil(p_pin text)
returns setof public.maa_hasil language plpgsql security definer set search_path = public as $$
begin
  if not public.maa_cek_pin(p_pin) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  return query select * from public.maa_hasil order by updated_at desc limit 5000;
end $$;

create or replace function public.maa_hapus_hasil(p_pin text, p_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.maa_cek_pin(p_pin) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  delete from public.maa_hasil where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.maa_ganti_pin(p_pin_lama text, p_pin_baru text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.maa_cek_pin(p_pin_lama) then raise exception 'PIN pengajar salah' using errcode = '28P01'; end if;
  if length(coalesce(p_pin_baru,'')) < 8 then raise exception 'PIN baru minimal 8 karakter'; end if;
  update public.maa_pengaturan set pin_hash = extensions.crypt(p_pin_baru, extensions.gen_salt('bf')) where id = 1;
end $$;

revoke all on function public.maa_kirim_hasil(jsonb) from public;
revoke all on function public.maa_ambil_hasil(text) from public;
revoke all on function public.maa_hapus_hasil(text, uuid[]) from public;
revoke all on function public.maa_ganti_pin(text, text) from public;
grant execute on function public.maa_kirim_hasil(jsonb) to anon, authenticated;
grant execute on function public.maa_ambil_hasil(text) to anon, authenticated;
grant execute on function public.maa_hapus_hasil(text, uuid[]) to anon, authenticated;
grant execute on function public.maa_ganti_pin(text, text) to anon, authenticated;
