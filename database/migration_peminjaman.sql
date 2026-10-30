-- ==============================================================================
-- MIGRASI SISTEM: TABEL PEMINJAMAN & PENINGKATAN AKSES MUTASI & USER
-- RSUD dr. R.T. Notopuro Sidoarjo - Logistik Tata Usaha
-- File: database/migration_peminjaman.sql
-- ==============================================================================

-- 1. TABEL PEMINJAMAN BARANG / ASET
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

-- 2. HAK AKSES DAN KEBIJAKAN ROW LEVEL SECURITY (RLS)
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON TABLE public.peminjaman TO anon, authenticated;
GRANT ALL ON TABLE public.mutasi TO anon, authenticated;
GRANT ALL ON TABLE public.profil_user TO anon, authenticated;
GRANT ALL ON TABLE public.barang TO anon, authenticated;

-- RLS Tabel Peminjaman
ALTER TABLE public.peminjaman ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "peminjaman_select_all" ON public.peminjaman;
CREATE POLICY "peminjaman_select_all" ON public.peminjaman FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "peminjaman_insert_all" ON public.peminjaman;
CREATE POLICY "peminjaman_insert_all" ON public.peminjaman FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "peminjaman_update_all" ON public.peminjaman;
CREATE POLICY "peminjaman_update_all" ON public.peminjaman FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

-- RLS Tabel Mutasi
ALTER TABLE public.mutasi ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mutasi_select_all" ON public.mutasi;
CREATE POLICY "mutasi_select_all" ON public.mutasi FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "mutasi_insert_all" ON public.mutasi;
CREATE POLICY "mutasi_insert_all" ON public.mutasi FOR INSERT TO anon, authenticated WITH CHECK (true);

-- RLS Tabel Profil User
ALTER TABLE public.profil_user ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profil_select_all" ON public.profil_user;
CREATE POLICY "profil_select_all" ON public.profil_user FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "profil_insert_all" ON public.profil_user;
CREATE POLICY "profil_insert_all" ON public.profil_user FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "profil_update_all" ON public.profil_user;
CREATE POLICY "profil_update_all" ON public.profil_user FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

-- Trigger updated_at pada peminjaman
DROP TRIGGER IF EXISTS trigger_peminjaman_updated_at ON public.peminjaman;
CREATE TRIGGER trigger_peminjaman_updated_at
    BEFORE UPDATE ON public.peminjaman
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Sample data peminjaman (untuk pengujian notifikasi keterlambatan)
-- Contoh data yang sudah lewat jatuh tempo (terlambat) dan yang masih berjalan
DO $$
DECLARE
    v_barang_id UUID;
BEGIN
    SELECT id INTO v_barang_id FROM public.barang LIMIT 1;
    IF v_barang_id IS NOT NULL THEN
        -- Sample 1: Peminjaman Terlambat (Batas waktu kemarin)
        INSERT INTO public.peminjaman (barang_id, nama_peminjam, nip_peminjam, unit_ruangan, jumlah, tanggal_ambil, batas_waktu_kembali, status, keterangan)
        VALUES (
            v_barang_id,
            'dr. Bambang Soedjatmiko, Sp.A',
            '197805122005011003',
            'Instalasi Rawat Inap Teratai',
            1,
            timezone('utc'::text, now() - INTERVAL '5 days'),
            timezone('utc'::text, now() - INTERVAL '2 days'),
            'dipinjam',
            'Peminjaman proyektor/perangkat presentasi rapat pelayanan medis'
        ) ON CONFLICT DO NOTHING;
    END IF;
END $$;
