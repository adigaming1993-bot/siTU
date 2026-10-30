-- ==============================================================================
-- SISTEM INVENTARIS LOGISTIK TATA USAHA - RSUD dr. R.T. NOTOPURO SIDOARJO
-- Skema Database PostgreSQL / Supabase dengan Row Level Security (RLS)
-- File: database/schema.sql
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. TIPE ENUM ROLE DAN MUTASI
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('staf_gudang', 'kepala_tu');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE jenis_mutasi AS ENUM ('masuk', 'keluar');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE status_mutasi AS ENUM ('draft', 'menunggu_persetujuan', 'disetujui', 'ditolak');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ==============================================================================
-- 3. TABEL PROFIL USER (profil_user)
-- Menyimpan informasi profil pegawai TU dan role hak akses (staf_gudang / kepala_tu)
-- Terhubung langsung dengan tabel autentikasi internal Supabase (auth.users)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.profil_user (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nama_lengkap VARCHAR(255) NOT NULL,
    nip VARCHAR(50) UNIQUE,
    role user_role NOT NULL DEFAULT 'staf_gudang',
    jabatan VARCHAR(100) DEFAULT 'Staf Logistik Tata Usaha',
    no_telepon VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ==============================================================================
-- 4. TABEL BARANG (barang)
-- Katalog inventaris barang logistik Bagian Tata Usaha RSUD dr. R.T. Notopuro
-- (ATK, kertas cetakan formulir rekam medis/administrasi, alat kebersihan, dsb)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.barang (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kode_barang VARCHAR(50) UNIQUE NOT NULL,
    nama VARCHAR(255) NOT NULL,
    kategori VARCHAR(100) NOT NULL,
    stok INTEGER NOT NULL DEFAULT 0 CHECK (stok >= 0),
    satuan VARCHAR(50) NOT NULL DEFAULT 'pcs',
    stok_minimum INTEGER NOT NULL DEFAULT 5 CHECK (stok_minimum >= 0),
    lokasi_rak VARCHAR(100),
    keterangan TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Indexing untuk pencarian cepat katalog barang
CREATE INDEX IF NOT EXISTS idx_barang_kategori ON public.barang(kategori);
CREATE INDEX IF NOT EXISTS idx_barang_nama ON public.barang(nama);
CREATE INDEX IF NOT EXISTS idx_barang_kode ON public.barang(kode_barang);

-- ==============================================================================
-- 5. TABEL MUTASI (mutasi)
-- Pencatatan riwayat transaksi barang masuk (pengadaan/drop) dan keluar (distribusi ke unit/poli)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.mutasi (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nomor_dokumen VARCHAR(100) NOT NULL, -- Nomor SBBK (Surat Bukti Barang Keluar) / BAP
    barang_id UUID NOT NULL REFERENCES public.barang(id) ON DELETE RESTRICT,
    jenis_mutasi jenis_mutasi NOT NULL,
    jumlah INTEGER NOT NULL CHECK (jumlah > 0),
    stok_sebelum INTEGER NOT NULL DEFAULT 0,
    stok_sesudah INTEGER NOT NULL DEFAULT 0,
    unit_tujuan_asal VARCHAR(150) NOT NULL, -- Asal pengadaan atau unit tujuan distribusi di RSUD
    keterangan TEXT,
    status status_mutasi NOT NULL DEFAULT 'disetujui',
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT, -- Staf yang mencatat
    disetujui_oleh UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Kepala TU yang memverifikasi
    tanggal_mutasi TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_mutasi_barang_id ON public.mutasi(barang_id);
CREATE INDEX IF NOT EXISTS idx_mutasi_jenis ON public.mutasi(jenis_mutasi);
CREATE INDEX IF NOT EXISTS idx_mutasi_tanggal ON public.mutasi(tanggal_mutasi DESC);
CREATE INDEX IF NOT EXISTS idx_mutasi_status ON public.mutasi(status);

-- ==============================================================================
-- 6. FUNGSI DAN TRIGGER OTOMATISASI
-- ==============================================================================

-- A. Helper: Mengambil role user yang sedang aktif tanpa recursive loop RLS
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS user_role AS $$
DECLARE
    current_role user_role;
BEGIN
    SELECT role INTO current_role
    FROM public.profil_user
    WHERE id = auth.uid();
    
    RETURN current_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

-- B. Trigger: Update timestamp 'updated_at' otomatis
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_profil_user_updated_at ON public.profil_user;
CREATE TRIGGER trigger_profil_user_updated_at
    BEFORE UPDATE ON public.profil_user
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_barang_updated_at ON public.barang;
CREATE TRIGGER trigger_barang_updated_at
    BEFORE UPDATE ON public.barang
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_mutasi_updated_at ON public.mutasi;
CREATE TRIGGER trigger_mutasi_updated_at
    BEFORE UPDATE ON public.mutasi
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- C. Trigger: Update otomatis stok barang saat mutasi disetujui / dicatat
CREATE OR REPLACE FUNCTION public.proses_mutasi_stok()
RETURNS TRIGGER AS $$
DECLARE
    v_stok_sekarang INTEGER;
BEGIN
    -- Ambil stok barang saat ini dengan locking baris (FOR UPDATE)
    SELECT stok INTO v_stok_sekarang
    FROM public.barang
    WHERE id = NEW.barang_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Barang dengan ID % tidak ditemukan.', NEW.barang_id;
    END IF;

    -- Simpan snapshot stok sebelum mutasi
    NEW.stok_sebelum := v_stok_sekarang;

    -- Proses mutasi masuk vs keluar jika status 'disetujui'
    IF NEW.status = 'disetujui' THEN
        IF NEW.jenis_mutasi = 'masuk' THEN
            NEW.stok_sesudah := v_stok_sekarang + NEW.jumlah;
            UPDATE public.barang
            SET stok = NEW.stok_sesudah
            WHERE id = NEW.barang_id;
        ELSIF NEW.jenis_mutasi = 'keluar' THEN
            IF v_stok_sekarang < NEW.jumlah THEN
                RAISE EXCEPTION 'Stok barang tidak mencukupi untuk mutasi keluar! Stok saat ini: %, Permintaan: %',
                    v_stok_sekarang, NEW.jumlah;
            END IF;
            NEW.stok_sesudah := v_stok_sekarang - NEW.jumlah;
            UPDATE public.barang
            SET stok = NEW.stok_sesudah
            WHERE id = NEW.barang_id;
        END IF;
    ELSE
        -- Jika status draft atau menunggu, stok sesudah tetap sama dengan stok sekarang
        NEW.stok_sesudah := v_stok_sekarang;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trigger_proses_mutasi_stok ON public.mutasi;
CREATE TRIGGER trigger_proses_mutasi_stok
    BEFORE INSERT ON public.mutasi
    FOR EACH ROW EXECUTE FUNCTION public.proses_mutasi_stok();

-- D. Trigger: Otomatis buat profil saat ada pendaftaran user baru di auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profil_user (id, nama_lengkap, nip, role, jabatan)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'nama_lengkap', NEW.email),
        NEW.raw_user_meta_data->>'nip',
        COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'staf_gudang'::user_role),
        COALESCE(NEW.raw_user_meta_data->>'jabatan', 'Staf Logistik Tata Usaha')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==============================================================================
-- 7. ROW LEVEL SECURITY (RLS) POLICIES
-- Pemisahan hak akses antara 'staf_gudang' dan 'kepala_tu'
--
-- Ringkasan Hak Akses:
-- | Tabel       | Aksi   | Staf Gudang                       | Kepala TU                   |
-- |-------------|--------|-----------------------------------|-----------------------------|
-- | profil_user | SELECT | Semua profil aktif                | Semua profil                |
-- | profil_user | UPDATE | Milik sendiri (kecuali role)      | Semua profil (bisa ubah role)|
-- | barang      | SELECT | Melihat semua barang              | Melihat semua barang        |
-- | barang      | INSERT | Menambah barang baru              | Menambah barang baru        |
-- | barang      | UPDATE | Memperbarui data barang/lokasi   | Memperbarui data barang     |
-- | barang      | DELETE | DITOLAK (cegah hapus sepihak)     | DIIZINKAN                   |
-- | mutasi      | SELECT | Melihat seluruh mutasi operasional| Melihat seluruh mutasi & audit|
-- | mutasi      | INSERT | Mencatat transaksi masuk/keluar  | Mencatat transaksi          |
-- | mutasi      | UPDATE | Hanya mutasi draft miliknya       | Persetujuan/Approval status |
-- | mutasi      | DELETE | Hanya draft miliknya              | Hapus draft/ditolak         |
-- ==============================================================================

-- Aktifkan RLS pada seluruh tabel
ALTER TABLE public.profil_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barang ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mutasi ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- A. KEBIJAKAN RLS: TABEL PROFIL_USER
-- ------------------------------------------------------------------------------

-- 1. Baca: Staf dan Kepala TU yang terautentikasi dapat membaca data profil user
CREATE POLICY "profil_select_authenticated"
    ON public.profil_user
    FOR SELECT
    TO authenticated
    USING (true);

-- 2. Tambah: User dapat memasukkan data profilnya sendiri
CREATE POLICY "profil_insert_own"
    ON public.profil_user
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

-- 3. Edit: Staf hanya dapat mengubah data profil miliknya sendiri (tanpa mengubah role)
CREATE POLICY "profil_update_own_staf"
    ON public.profil_user
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id AND public.get_current_user_role() = 'staf_gudang')
    WITH CHECK (auth.uid() = id AND role = 'staf_gudang');

-- 4. Edit: Kepala TU dapat mengubah profil user manapun termasuk mengelola role
CREATE POLICY "profil_update_kepala_tu"
    ON public.profil_user
    FOR UPDATE
    TO authenticated
    USING (public.get_current_user_role() = 'kepala_tu')
    WITH CHECK (public.get_current_user_role() = 'kepala_tu');

-- 5. Larangan Penghapusan Fisik (Soft Delete Mekanisme):
-- Operasi DELETE dilarang demi menjaga integritas data & foreign key mutasi logistik.
-- Pencabutan akses staf dilakukan melalui pembaruan kolom 'is_active = false'.
REVOKE DELETE ON TABLE public.profil_user FROM anon, authenticated, public;
DROP POLICY IF EXISTS "profil_delete_kepala_tu" ON public.profil_user;
-- ------------------------------------------------------------------------------
-- B. KEBIJAKAN RLS: TABEL BARANG
-- ------------------------------------------------------------------------------

-- 1. Baca: Mengizinkan akses publik/anon dan authenticated untuk melihat katalog barang
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.barang TO anon, authenticated;

CREATE POLICY "barang_select_public_and_auth"
    ON public.barang
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 2. Tambah: Baik Staf Gudang maupun Kepala TU dapat menambahkan barang baru
CREATE POLICY "barang_insert_staff_and_head"
    ON public.barang
    FOR INSERT
    TO authenticated
    WITH CHECK (
        public.get_current_user_role() IN ('staf_gudang', 'kepala_tu')
    );

-- 3. Edit: Staf Gudang dan Kepala TU dapat memperbarui detail barang (nama, kategori, rak, dll)
CREATE POLICY "barang_update_staff_and_head"
    ON public.barang
    FOR UPDATE
    TO authenticated
    USING (
        public.get_current_user_role() IN ('staf_gudang', 'kepala_tu')
    )
    WITH CHECK (
        public.get_current_user_role() IN ('staf_gudang', 'kepala_tu')
    );

-- 4. Hapus: Hanya Kepala TU yang berwenang menghapus master data barang dari sistem
CREATE POLICY "barang_delete_only_kepala_tu"
    ON public.barang
    FOR DELETE
    TO authenticated
    USING (public.get_current_user_role() = 'kepala_tu');

-- ------------------------------------------------------------------------------
-- C. KEBIJAKAN RLS: TABEL MUTASI
-- ------------------------------------------------------------------------------

-- 1. Baca: Semua pegawai TU yang terautentikasi dapat melihat riwayat mutasi barang
CREATE POLICY "mutasi_select_authenticated"
    ON public.mutasi
    FOR SELECT
    TO authenticated
    USING (true);

-- 2. Tambah: Staf Gudang dan Kepala TU dapat mencatat mutasi masuk/keluar
CREATE POLICY "mutasi_insert_staff_and_head"
    ON public.mutasi
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = user_id AND
        public.get_current_user_role() IN ('staf_gudang', 'kepala_tu')
    );

-- 3. Edit oleh Staf Gudang: Hanya bisa memperbarui transaksi bertatus 'draft' miliknya sendiri
CREATE POLICY "mutasi_update_staf_own_draft"
    ON public.mutasi
    FOR UPDATE
    TO authenticated
    USING (
        public.get_current_user_role() = 'staf_gudang' AND
        user_id = auth.uid() AND
        status = 'draft'
    )
    WITH CHECK (
        user_id = auth.uid() AND
        status IN ('draft', 'menunggu_persetujuan')
    );

-- 4. Edit oleh Kepala TU: Kepala TU memiliki wewenang approval/verifikasi untuk seluruh mutasi
CREATE POLICY "mutasi_update_kepala_tu_approval"
    ON public.mutasi
    FOR UPDATE
    TO authenticated
    USING (public.get_current_user_role() = 'kepala_tu')
    WITH CHECK (public.get_current_user_role() = 'kepala_tu');

-- 5. Hapus oleh Staf Gudang: Staf hanya dapat membatalkan/menghapus draft miliknya sendiri
CREATE POLICY "mutasi_delete_staf_own_draft"
    ON public.mutasi
    FOR DELETE
    TO authenticated
    USING (
        public.get_current_user_role() = 'staf_gudang' AND
        user_id = auth.uid() AND
        status = 'draft'
    );

-- 6. Hapus oleh Kepala TU: Kepala TU dapat membersihkan data mutasi draft atau ditolak
CREATE POLICY "mutasi_delete_kepala_tu"
    ON public.mutasi
    FOR DELETE
    TO authenticated
    USING (
        public.get_current_user_role() = 'kepala_tu' AND
        status IN ('draft', 'ditolak')
    );

-- ==============================================================================
-- 8. DATA AWAL SAMPLE / SEED (Untuk Pengujian Awal RSUD dr. R.T. Notopuro)
-- ==============================================================================
INSERT INTO public.barang (kode_barang, nama, kategori, stok, satuan, stok_minimum, lokasi_rak, keterangan)
VALUES 
    ('TU-ATK-001', 'Kertas HVS A4 75 GSM', 'Alat Tulis Kantor', 150, 'rim', 20, 'Rak A-1 Logistik TU', 'Pengadaan rutin untuk administrasi rumah sakit'),
    ('TU-ATK-002', 'Kertas HVS F4 / Folio 75 GSM', 'Alat Tulis Kantor', 100, 'rim', 15, 'Rak A-2 Logistik TU', 'Digunakan untuk berkas rekam medik & surat keputusan'),
    ('TU-ATK-003', 'Bolpoin Standard AE7 Hitam', 'Alat Tulis Kantor', 240, 'buah', 30, 'Rak B-1 Logistik TU', 'Distribusi rutin per poli & ruangan'),
    ('TU-CTK-001', 'Formulir Catatan Perkembangan Pasien Terintegrasi (CPPT)', 'Cetakan & Formulir', 50, 'rim', 10, 'Rak C-1 Cetakan RSUD', 'Formulir resmi rawat inap dan rawat jalan'),
    ('TU-CTK-002', 'Map Rekam Medik Pasien Baru', 'Cetakan & Formulir', 1200, 'buah', 200, 'Rak C-3 Cetakan RSUD', 'Map rekam medik loket pendaftaran'),
    ('TU-KBS-001', 'Hand Sanitizer Gel 500ml', 'Kebersihan & Sanitasi Non-Medis', 85, 'botol', 15, 'Rak D-1 Kebersihan', 'Penempatan di meja loket TU dan administrasi umum'),
    ('TU-KBS-002', 'Cairan Disinfektan Ruangan 5 Liter', 'Kebersihan & Sanitasi Non-Medis', 30, 'jerigen', 5, 'Gudang Bawah Logistik', 'Untuk desinfeksi rutin ruangan TU dan administrasi')
ON CONFLICT (kode_barang) DO NOTHING;

-- ==============================================================================
-- 9. TABEL PELACAKAN PEMINJAMAN ASET / BARANG LOGISTIK TU
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.peminjaman (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    barang_id UUID NOT NULL REFERENCES public.barang(id) ON DELETE RESTRICT,
    nama_peminjam VARCHAR(255) NOT NULL,
    nip_peminjam VARCHAR(50),
    unit_ruangan VARCHAR(150) NOT NULL,
    jumlah INTEGER NOT NULL DEFAULT 1 CHECK (jumlah > 0),
    tanggal_ambil TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    batas_waktu_kembali TIMESTAMPTZ NOT NULL,
    tanggal_kembali TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'dipinjam' CHECK (status IN ('dipinjam', 'kembali', 'terlambat')),
    keterangan TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_peminjaman_barang ON public.peminjaman(barang_id);
CREATE INDEX IF NOT EXISTS idx_peminjaman_status ON public.peminjaman(status);
CREATE INDEX IF NOT EXISTS idx_peminjaman_batas_waktu ON public.peminjaman(batas_waktu_kembali);

GRANT ALL ON TABLE public.peminjaman TO anon, authenticated;
ALTER TABLE public.peminjaman ENABLE ROW LEVEL SECURITY;

CREATE POLICY "peminjaman_select_all" ON public.peminjaman FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "peminjaman_insert_all" ON public.peminjaman FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "peminjaman_update_all" ON public.peminjaman FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

DROP TRIGGER IF EXISTS trigger_peminjaman_updated_at ON public.peminjaman;
CREATE TRIGGER trigger_peminjaman_updated_at
    BEFORE UPDATE ON public.peminjaman
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
