import { getSupabaseConfig } from '../lib/supabase.js';

/**
 * Serverless Function Vercel: /api/config
 * Mengembalikan konfigurasi publik Supabase (URL dan Anon Key) untuk diakses oleh client frontend.
 * Aman karena Anon Key memang dirancang oleh Supabase untuk dipublikasikan ke client browser.
 */
export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Authorization'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    res.setHeader('Allow', ['GET', 'OPTIONS']);
    return res.status(405).json({ success: false, error: 'Metode tidak diizinkan' });
  }

  try {
    const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig();
    return res.status(200).json({
      success: true,
      supabaseUrl,
      supabaseAnonKey,
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      error: err.message,
    });
  }
}
