-- ==============================================================================
-- MIGRASI SISTEM: PERAN AKSES, KONDISI PENGEMBALIAN & HAK AKSES DELETE USER
-- RSUD dr. R.T. Notopuro Sidoarjo - SIAPIN (Sistem Aplikasi Peminjaman Inventaris)
-- File: database/migration_role_and_peminjaman_status.sql
-- ==============================================================================

-- 1. Pastikan kolom role pada tabel profil_user dapat menampung teks role baru
-- ('Staf' dan 'Kepala Sub Bagian Tata Usaha dan Rumah Tangga')
ALTER TABLE public.profil_user ALTER COLUMN role TYPE VARCHAR(150);
ALTER TABLE public.profil_user ALTER COLUMN jabatan TYPE VARCHAR(150);

-- 2. Perbarui batasan status pada tabel peminjaman agar mendukung 3 kondisi pengembalian:
-- 'Kembali' (Normal), 'Kembali - Rusak', dan 'Mutasi'
ALTER TABLE public.peminjaman DROP CONSTRAINT IF EXISTS peminjaman_status_check;
ALTER TABLE public.peminjaman ADD CONSTRAINT peminjaman_status_check 
    CHECK (status IN (
        'dipinjam', 'kembali', 'terlambat', 
        'Kembali', 'Kembali - Rusak', 'Mutasi',
        'kembali - rusak', 'mutasi'
    ));

-- 3. Kebijakan RLS untuk DELETE pada profil_user
-- Memastikan staf terhapus benar-benar dapat dihapus dan diblokir dari sistem
DROP POLICY IF EXISTS "profil_delete_all" ON public.profil_user;
CREATE POLICY "profil_delete_all" 
ON public.profil_user 
FOR DELETE 
TO anon, authenticated 
USING (true);

-- 4. Berikan izin hak akses table profil_user dan peminjaman
GRANT ALL ON TABLE public.profil_user TO anon, authenticated;
GRANT ALL ON TABLE public.peminjaman TO anon, authenticated;
GRANT ALL ON TABLE public.barang TO anon, authenticated;
