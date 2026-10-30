-- ==============================================================================
-- MIGRASI KEAMANAN: SISTEM NONAKTIF (SOFT DELETE) & LARANGAN DELETE PROFIL USER
-- RSUD dr. R.T. Notopuro Sidoarjo - Logistik Tata Usaha
-- File: database/migration_soft_delete_user.sql
-- ==============================================================================

-- 1. Pastikan kolom is_active tersedia pada tabel profil_user
ALTER TABLE public.profil_user 
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_profil_user_active ON public.profil_user(is_active);

-- 2. CABUT SEMUA HAK AKSES DELETE PADA TABEL PROFIL_USER
-- Mencegah penghapusan fisik baris demi menjaga integritas foreign key pada audit trail transaksi mutasi
REVOKE DELETE ON TABLE public.profil_user FROM anon, authenticated, public;

-- Hapus kebijakan RLS DELETE jika sebelumnya ada
DROP POLICY IF EXISTS "profil_delete_kepala_tu" ON public.profil_user;
DROP POLICY IF EXISTS "profil_delete_all" ON public.profil_user;

-- 3. Kebijakan RLS: Izinkan SELECT, INSERT, dan UPDATE (untuk ubah is_active)
ALTER TABLE public.profil_user ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profil_select_all" ON public.profil_user;
CREATE POLICY "profil_select_all" 
    ON public.profil_user 
    FOR SELECT 
    TO anon, authenticated 
    USING (true);

DROP POLICY IF EXISTS "profil_insert_all" ON public.profil_user;
CREATE POLICY "profil_insert_all" 
    ON public.profil_user 
    FOR INSERT 
    TO anon, authenticated 
    WITH CHECK (true);

DROP POLICY IF EXISTS "profil_update_all" ON public.profil_user;
CREATE POLICY "profil_update_all" 
    ON public.profil_user 
    FOR UPDATE 
    TO anon, authenticated 
    USING (true) 
    WITH CHECK (true);

-- Catatan Keamanan:
-- Tidak ada kebijakan FOR DELETE pada public.profil_user.
-- Setiap staf yang dimutasi / pindah tugas dinonaktifkan dengan:
-- UPDATE public.profil_user SET is_active = false WHERE id = '<user_id>';
