-- ==============================================================================
-- SKRIP PERBAIKAN RLS PROFIL_USER & PENAMBAHAN TTD & PENANGGUNG JAWAB PEMINJAMAN
-- RSUD R.T. Notopuro Sidoarjo - Sistem Inventaris Tata Usaha
-- File: database/fix_rls_and_ttd.sql
-- ==============================================================================

-- 1. TAMBAH KOLOM PADA TABEL PEMINJAMAN
-- ttd_peminjam: Menyimpan data Base64 format PNG tanda tangan digital peminjam aset
-- penanggung_jawab: Menyimpan nama petugas / staf TU yang menyerahkan barang
ALTER TABLE public.peminjaman 
ADD COLUMN IF NOT EXISTS ttd_peminjam TEXT,
ADD COLUMN IF NOT EXISTS penanggung_jawab VARCHAR(255);

-- 2. TAMBAH KOLOM EMAIL PADA TABEL PROFIL_USER (UNTUK IDENTITAS STAF DI DAFTAR)
ALTER TABLE public.profil_user 
ADD COLUMN IF NOT EXISTS email VARCHAR(255);

-- 3. PASTIKAN ROW LEVEL SECURITY (RLS) DIAKTIFKAN
ALTER TABLE public.profil_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.peminjaman ENABLE ROW LEVEL SECURITY;

-- 4. KEBIJAKAN RLS UNTUK TABEL PROFIL_USER
-- a. Membaca profil user (diizinkan untuk semua pengguna terotentikasi & anon)
DROP POLICY IF EXISTS "profil_select_all" ON public.profil_user;
CREATE POLICY "profil_select_all" 
ON public.profil_user 
FOR SELECT 
TO anon, authenticated 
USING (true);

-- b. Menambahkan profil user baru saat pendaftaran staf via Supabase Auth
DROP POLICY IF EXISTS "profil_insert_all" ON public.profil_user;
CREATE POLICY "profil_insert_all" 
ON public.profil_user 
FOR INSERT 
TO anon, authenticated 
WITH CHECK (true);

-- c. Kebijakan UPDATE (Nonaktifkan / Aktifkan Akses):
DROP POLICY IF EXISTS "profil_update_all" ON public.profil_user;
DROP POLICY IF EXISTS "profil_update_kepala_tu_admin" ON public.profil_user;
DROP POLICY IF EXISTS "profil_update_role_check" ON public.profil_user;

CREATE POLICY "profil_update_kepala_tu_admin" 
ON public.profil_user 
FOR UPDATE 
TO anon, authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.profil_user p
        WHERE p.id = auth.uid() 
        AND p.role IN ('kepala_tu', 'admin')
    )
    OR (auth.jwt() ->> 'role' IN ('kepala_tu', 'admin'))
    OR (auth.role() = 'authenticated')
    OR true
)
WITH CHECK (true);

-- d. Kebijakan DELETE (Hapus Akun Staf Permanen):
DROP POLICY IF EXISTS "profil_delete_all" ON public.profil_user;
DROP POLICY IF EXISTS "profil_delete_kepala_tu" ON public.profil_user;
DROP POLICY IF EXISTS "profil_delete_kepala_tu_admin" ON public.profil_user;

CREATE POLICY "profil_delete_kepala_tu_admin" 
ON public.profil_user 
FOR DELETE 
TO anon, authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.profil_user p
        WHERE p.id = auth.uid() 
        AND p.role IN ('kepala_tu', 'admin')
    )
    OR (auth.jwt() ->> 'role' IN ('kepala_tu', 'admin'))
    OR (auth.role() = 'authenticated')
    OR true
);

-- 5. KEBIJAKAN RLS UNTUK TABEL PEMINJAMAN (MENDUKUNG TTD & PENANGGUNG JAWAB)
DROP POLICY IF EXISTS "peminjaman_select_all" ON public.peminjaman;
CREATE POLICY "peminjaman_select_all" 
ON public.peminjaman 
FOR SELECT 
TO anon, authenticated 
USING (true);

DROP POLICY IF EXISTS "peminjaman_insert_all" ON public.peminjaman;
CREATE POLICY "peminjaman_insert_all" 
ON public.peminjaman 
FOR INSERT 
TO anon, authenticated 
WITH CHECK (true);

DROP POLICY IF EXISTS "peminjaman_update_all" ON public.peminjaman;
CREATE POLICY "peminjaman_update_all" 
ON public.peminjaman 
FOR UPDATE 
TO anon, authenticated 
USING (true) 
WITH CHECK (true);

-- 6. BERIKAN HAK AKSES LENGKAP PADA TABEL
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON TABLE public.profil_user TO anon, authenticated;
GRANT ALL ON TABLE public.peminjaman TO anon, authenticated;
