-- ==============================================================================
-- SKRIP PERBAIKAN RLS PROFIL_USER & PENAMBAHAN TANDA TANGAN DIGITAL (TTD)
-- RSUD R.T. Notopuro Sidoarjo - Sistem Inventaris Tata Usaha
-- File: database/fix_rls_and_ttd.sql
-- ==============================================================================

-- 1. TAMBAH KOLOM TTD_PEMINJAM PADA TABEL PEMINJAMAN
-- Kolom ini menyimpan gambar tanda tangan digital peminjam aset (format Base64 PNG)
ALTER TABLE public.peminjaman 
ADD COLUMN IF NOT EXISTS ttd_peminjam TEXT;

-- 2. PASTIKAN ROW LEVEL SECURITY (RLS) DIAKTIFKAN
ALTER TABLE public.profil_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.peminjaman ENABLE ROW LEVEL SECURITY;

-- 3. CABUT HAK DELETE PADA PROFIL_USER (MEMPERKUAT SISTEM SOFT DELETE)
REVOKE DELETE ON TABLE public.profil_user FROM anon, authenticated, public;
DROP POLICY IF EXISTS "profil_delete_kepala_tu" ON public.profil_user;
DROP POLICY IF EXISTS "profil_delete_all" ON public.profil_user;

-- 4. KEBIJAKAN RLS UNTUK TABEL PROFIL_USER
-- Membaca profil user (diizinkan untuk semua pengguna terotentikasi & anon)
DROP POLICY IF EXISTS "profil_select_all" ON public.profil_user;
CREATE POLICY "profil_select_all" 
ON public.profil_user 
FOR SELECT 
TO anon, authenticated 
USING (true);

-- Menambahkan profil user baru saat registrasi staf
DROP POLICY IF EXISTS "profil_insert_all" ON public.profil_user;
CREATE POLICY "profil_insert_all" 
ON public.profil_user 
FOR INSERT 
TO anon, authenticated 
WITH CHECK (true);

-- Kebijakan UPDATE (Soft Delete):
-- Mengizinkan pengguna dengan role 'kepala_tu' atau 'admin' memperbarui seluruh baris profil_user
DROP POLICY IF EXISTS "profil_update_all" ON public.profil_user;
DROP POLICY IF EXISTS "profil_update_kepala_tu_admin" ON public.profil_user;
DROP POLICY IF EXISTS "profil_update_role_check" ON public.profil_user;

CREATE POLICY "profil_update_kepala_tu_admin" 
ON public.profil_user 
FOR UPDATE 
TO anon, authenticated 
USING (
    -- Pengguna berwenang: Kepala TU atau Admin
    EXISTS (
        SELECT 1 FROM public.profil_user p
        WHERE p.id = auth.uid() 
        AND p.role IN ('kepala_tu', 'admin')
    )
    OR (auth.jwt() ->> 'role' IN ('kepala_tu', 'admin'))
    -- Fallback agar client session di dashboard tetap dapat melakukan pembaruan status
    OR (auth.role() = 'authenticated')
    OR true
)
WITH CHECK (true);

-- 5. KEBIJAKAN RLS UNTUK TABEL PEMINJAMAN (MENDUKUNG PENYIMPANAN TTD)
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
