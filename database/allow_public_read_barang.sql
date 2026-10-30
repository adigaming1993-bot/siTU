-- ==============================================================================
-- SKRIP SEMENTARA: IZINKAN AKSES BACA PUBLIK (ANON) PADA TABEL BARANG
-- RSUD dr. R.T. Notopuro Sidoarjo - Sistem Inventaris Tata Usaha
-- File: database/allow_public_read_barang.sql
-- ==============================================================================

-- 1. Berikan hak akses SELECT tingkat database ke role 'anon' (pengunjung tanpa token login)
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.barang TO anon, authenticated;

-- 2. Hapus kebijakan SELECT lama yang hanya membatasi 'authenticated'
DROP POLICY IF EXISTS "barang_select_authenticated" ON public.barang;
DROP POLICY IF EXISTS "barang_select_public_anon" ON public.barang;

-- 3. Buat kebijakan RLS baru yang mengizinkan publik (anon) dan authenticated membaca katalog barang
CREATE POLICY "barang_select_public_anon"
    ON public.barang
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- Catatan:
-- Operasi INSERT, UPDATE, dan DELETE pada tabel barang TETAP DILINDUNGI
-- dan hanya bisa dilakukan oleh staf_gudang / kepala_tu yang terautentikasi.

-- ==============================================================================
-- CARA MENGEMBALIKAN KE MODE RESTRIKTIF (Jika nanti sistem autentikasi sudah aktif):
-- ==============================================================================
-- DROP POLICY IF EXISTS "barang_select_public_anon" ON public.barang;
-- CREATE POLICY "barang_select_authenticated"
--     ON public.barang
--     FOR SELECT
--     TO authenticated
--     USING (true);
