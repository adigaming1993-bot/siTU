import { getSupabaseClient } from '../lib/supabase.js';

/**
 * Serverless Function Vercel: /api/barang
 * Mengambil daftar inventaris barang logistik Tata Usaha di RSUD dr. R.T. Notopuro dari Supabase.
 *
 * Query Parameters:
 * - kategori: Filter berdasarkan kategori (contoh: "Alat Tulis Kantor")
 * - search / q: Pencarian teks pada nama barang
 * - stok_kritis: true/false - Menampilkan barang dengan stok <= stok_minimum (jika kolom tersedia)
 * - limit: Batas jumlah data yang diambil (default: 50, maks: 100)
 * - offset: Offset data untuk paginasi (default: 0)
 * - sort: Urutkan berdasarkan kolom (default: 'nama')
 * - order: 'asc' atau 'desc' (default: 'asc')
 *
 * @param {import('http').IncomingMessage & { query: Object, body: any }} req
 * @param {import('http').ServerResponse & { status: Function, json: Function }} res
 */
export default async function handler(req, res) {
  // Atur header CORS yang valid (hindari konflik wildcard '*' dengan allow-credentials)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Authorization'
  );

  // Tangani HTTP OPTIONS preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Hanya izinkan metode GET untuk endpoint ini
  if (req.method !== 'GET') {
    res.setHeader('Allow', ['GET', 'OPTIONS']);
    return res.status(405).json({
      success: false,
      error: `Metode HTTP '${req.method}' tidak diizinkan. Gunakan GET untuk mengambil daftar barang.`,
    });
  }

  try {
    // Inisialisasi Supabase client (meneruskan header Authorization jika ada)
    const supabase = getSupabaseClient(req);

    // Parsing parameter query
    const {
      kategori,
      search,
      q,
      stok_kritis,
      limit = '50',
      offset = '0',
      sort = 'nama',
      order = 'asc',
    } = req.query || {};

    const limitNumber = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
    const offsetNumber = Math.max(parseInt(offset, 10) || 0, 0);
    const isAscending = order.toLowerCase() === 'asc';
    const keyword = search || q;

    // Gunakan select('*') agar tidak gagal jika ada variasi struktur kolom
    let query = supabase.from('barang').select('*', { count: 'exact' });

    // Filter berdasarkan kategori jika disediakan
    if (kategori) {
      query = query.eq('kategori', kategori);
    }

    // Filter pencarian nama
    if (keyword) {
      query = query.ilike('nama', `%${keyword}%`);
    }

    // Filter stok kritis jika diminta
    if (stok_kritis === 'true' || stok_kritis === true) {
      query = query.filter('stok', 'lte', 'stok_minimum');
    }

    // Paginasi dan pengurutan
    try {
      query = query
        .order(sort, { ascending: isAscending })
        .range(offsetNumber, offsetNumber + limitNumber - 1);
    } catch {
      // Fallback tanpa order jika kolom sort tidak ada
      query = query.range(offsetNumber, offsetNumber + limitNumber - 1);
    }

    // Eksekusi query ke Supabase
    const { data, count, error } = await query;

    if (error) {
      console.error('[API Error /api/barang]: Gagal membaca dari Supabase:', error);

      // Diagnosis spesifik kode error PostgreSQL / Supabase
      if (error.code === '42501') {
        return res.status(403).json({
          success: false,
          error: 'Akses ditolak oleh kebijakan Row Level Security (RLS) Supabase.',
          solusi: 'Jalankan perintah SQL berikut di Supabase SQL Editor: ALTER TABLE public.barang DISABLE ROW LEVEL SECURITY; atau pasang policy SELECT untuk role anon.',
          details: error.message,
        });
      }

      if (error.code === '42P01') {
        return res.status(404).json({
          success: false,
          error: 'Tabel "barang" belum ditemukan di database Supabase.',
          solusi: 'Buka menu SQL Editor di Supabase Dashboard, lalu jalankan isi berkas database/schema.sql untuk membuat tabel.',
          details: error.message,
        });
      }

      return res.status(500).json({
        success: false,
        error: 'Terjadi kesalahan saat mengambil data barang dari Supabase.',
        code: error.code,
        details: error.message,
      });
    }

    // Berikan respons sukses
    return res.status(200).json({
      success: true,
      instansi: 'RSUD dr. R.T. Notopuro Sidoarjo - Bagian Tata Usaha',
      message: 'Berhasil mengambil daftar barang logistik.',
      meta: {
        total: count ?? (data ? data.length : 0),
        limit: limitNumber,
        offset: offsetNumber,
        count: data ? data.length : 0,
      },
      data: data || [],
    });
  } catch (err) {
    console.error('[API Exception /api/barang]:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'Terjadi kesalahan internal pada server.',
      solusi: err.message?.includes('Kredensial')
        ? 'Pastikan variabel SUPABASE_URL dan SUPABASE_ANON_KEY telah diatur pada Environment Variables di Vercel Dashboard.'
        : undefined,
    });
  }
}
