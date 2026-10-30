import { getSupabaseClient } from '../lib/supabase.js';

/**
 * Serverless Function Vercel: /api/barang
 * Mengambil daftar inventaris barang logistik Tata Usaha di RSUD dr. R.T. Notopuro dari Supabase.
 *
 * Query Parameters:
 * - kategori: Filter berdasarkan kategori (contoh: "Alat Tulis Kantor", "Cetakan & Formulir")
 * - search / q: Pencarian teks pada nama atau kode barang
 * - stok_kritis: true/false - Menampilkan barang dengan stok <= stok_minimum (peringatan restock)
 * - limit: Batas jumlah data yang diambil (default: 50, maks: 100)
 * - offset: Offset data untuk paginasi (default: 0)
 * - sort: Urutkan berdasarkan kolom (default: 'nama')
 * - order: 'asc' atau 'desc' (default: 'asc')
 *
 * @param {import('http').IncomingMessage & { query: Object, body: any }} req
 * @param {import('http').ServerResponse & { status: Function, json: Function }} res
 */
export default async function handler(req, res) {
  // Atur header CORS
  res.setHeader('Access-Control-Allow-Credentials', 'true');
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
    // Inisialisasi Supabase client (mewarisi token otentikasi user jika ada)
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

    // Susun query ke tabel 'barang'
    let query = supabase
      .from('barang')
      .select('id, kode_barang, nama, kategori, stok, satuan, stok_minimum, lokasi_rak, keterangan, created_at, updated_at', {
        count: 'exact',
      });

    // Filter berdasarkan kategori jika disediakan
    if (kategori) {
      query = query.eq('kategori', kategori);
    }

    // Filter pencarian nama atau kode barang
    if (keyword) {
      query = query.or(`nama.ilike.%${keyword}%,kode_barang.ilike.%${keyword}%`);
    }

    // Filter stok kritis (di bawah atau sama dengan stok minimum)
    if (stok_kritis === 'true' || stok_kritis === true) {
      query = query.filter('stok', 'lte', 'stok_minimum');
    }

    // Urutan dan paginasi
    const allowedSortFields = ['nama', 'kode_barang', 'kategori', 'stok', 'created_at', 'updated_at'];
    const sortField = allowedSortFields.includes(sort) ? sort : 'nama';

    query = query
      .order(sortField, { ascending: isAscending })
      .range(offsetNumber, offsetNumber + limitNumber - 1);

    // Eksekusi query
    const { data, count, error } = await query;

    if (error) {
      console.error('[API Error /api/barang]: Gagal membaca dari Supabase:', error);
      return res.status(500).json({
        success: false,
        error: 'Terjadi kesalahan saat mengambil data barang dari Supabase.',
        details: error.message,
      });
    }

    // Return response sukses
    return res.status(200).json({
      success: true,
      instansi: 'RSUD dr. R.T. Notopuro Sidoarjo - Bagian Tata Usaha',
      message: 'Berhasil mengambil daftar barang logistik.',
      meta: {
        total: count ?? data.length,
        limit: limitNumber,
        offset: offsetNumber,
        count: data.length,
      },
      data,
    });
  } catch (err) {
    console.error('[API Exception /api/barang]:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'Terjadi kesalahan internal pada server.',
    });
  }
}
