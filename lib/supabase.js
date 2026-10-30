import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

// Muat variabel lingkungan untuk mode development lokal
dotenv.config();

export function getSupabaseConfig() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      'Kredensial Supabase belum lengkap. Pastikan SUPABASE_URL dan SUPABASE_ANON_KEY telah diatur pada file .env atau Vercel Environment Variables.'
    );
  }

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
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
};

export const supabase = (process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY)
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    })
  : null;

export default getSupabaseClient;
