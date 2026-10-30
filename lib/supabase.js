import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

// Muat berkas .env jika ada (mode lokal)
dotenv.config();

/**
 * Mengambil dan memvalidasi konfigurasi kredensial Supabase.
 * Mendukung variasi nama environment variable standar (SUPABASE_URL, NEXT_PUBLIC_SUPABASE_URL, dsb).
 * Mendukung SUPABASE_SERVICE_ROLE_KEY untuk bypass RLS di level backend Vercel secara otomatis.
 */
export function getSupabaseConfig() {
  const rawUrl =
    process.env.SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL ||
    process.env.VITE_SUPABASE_URL;

  // Prioritaskan service_role key jika tersedia di backend Vercel untuk bypass batasan RLS
  const rawKey =
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    process.env.SUPABASE_KEY;

  if (!rawUrl || !rawKey) {
    throw new Error(
      'Kredensial Supabase belum lengkap. Pastikan SUPABASE_URL dan SUPABASE_ANON_KEY (atau SUPABASE_SERVICE_ROLE_KEY) telah diatur pada Vercel Environment Variables.'
    );
  }

  // Sanitasi: hilangkan spasi tidak sengaja dan trailing slash
  const supabaseUrl = rawUrl.trim().replace(/\/+$/, '');
  const supabaseAnonKey = rawKey.trim();

  return { supabaseUrl, supabaseAnonKey };
}

/**
 * Validasi keberadaan konfigurasi kredensial Supabase
 */
export function validateSupabaseConfig() {
  return getSupabaseConfig();
}

/**
 * Membuat instance client Supabase.
 * Jika request HTTP memiliki header 'Authorization' (Bearer token dari user login),
 * token tersebut akan diteruskan ke Supabase agar Row Level Security (RLS) berlaku sesuai role user (staf_gudang / kepala_tu).
 *
 * @param {import('http').IncomingMessage | Object} [req]
 * @returns {import('@supabase/supabase-js').SupabaseClient}
 */
export function getSupabaseClient(req) {
  const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig();

  const authHeader = req?.headers?.authorization || req?.headers?.Authorization;

  const clientOptions = {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  };

  // Teruskan JWT token user jika ada
  if (authHeader) {
    clientOptions.global = {
      headers: {
        Authorization: authHeader,
      },
    };
  }

  return createClient(supabaseUrl, supabaseAnonKey, clientOptions);
}

// Client instans default jika variabel lingkungan sudah tersedia
export const getSupabase = () => {
  try {
    const { supabaseUrl, supabaseAnonKey } = getSupabaseConfig();
    return createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });
  } catch {
    return null;
  }
};

export const supabase = getSupabase();

export default getSupabaseClient;
