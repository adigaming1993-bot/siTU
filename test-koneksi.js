import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import fs from 'fs';

// Muat file .env jika ada
if (fs.existsSync('.env')) {
  dotenv.config();
  console.log('📄 Berkas .env ditemukan dan dimuat.');
} else {
  console.warn('⚠️ Peringatan: Berkas .env belum ditemukan di direktori utama.');
  console.warn('   Pastikan Anda telah menyalin .env.example menjadi .env dan mengisi kredensial.');
}

const rawUrl =
  process.env.SUPABASE_URL ||
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  process.env.VITE_SUPABASE_URL;

const rawKey =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.SUPABASE_KEY;

const supabaseUrl = rawUrl ? rawUrl.trim().replace(/\/+$/, '') : null;
const supabaseKey = rawKey ? rawKey.trim() : null;

console.log('====================================================');
console.log('🔍 PENGUJIAN KONEKSI SUPABASE: /api/barang DEBUG');
console.log('====================================================');
console.log(`URL Supabase     : ${supabaseUrl ? supabaseUrl : '(KOSONG / BELUM DIISI)'}`);
console.log(`Key Supabase     : ${supabaseKey ? `${supabaseKey.substring(0, 15)}... (tersedia)` : '(KOSONG / BELUM DIISI)'}`);
console.log('----------------------------------------------------');

if (!supabaseUrl || !supabaseKey || supabaseUrl.includes('your-project-id')) {
  console.error('❌ GAGAL: Kredensial Supabase di .env belum valid atau masih menggunakan template.');
  console.error('👉 Silakan buat file .env dan isi dengan kredensial asli project Supabase Anda:');
  console.error('   SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co');
  console.error('   SUPABASE_ANON_KEY=eyJhbGciOi...');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: { persistSession: false },
});

async function testConnection() {
  console.log("⏳ Menjalankan query: supabase.from('barang').select('*').limit(1)...\n");

  try {
    const startTime = Date.now();
    const { data, count, error, status, statusText } = await supabase
      .from('barang')
      .select('*', { count: 'exact' })
      .limit(1);

    const duration = Date.now() - startTime;
    console.log(`⏱️ Waktu respons: ${duration}ms | Status HTTP: ${status} ${statusText || ''}`);

    if (error) {
      console.error('❌ Terjadi error saat query:');
      console.error(JSON.stringify(error, null, 2));

      if (error.code === '42501' || error.message?.toLowerCase().includes('permission denied') || error.message?.toLowerCase().includes('row-level security')) {
        console.error('\n🚨 DIAGNOSIS MASALAH:');
        console.error('Akses diblokir oleh kebijakan Row Level Security (RLS) pada PostgreSQL/Supabase.');
        console.error('Solusi: Buka Supabase SQL Editor dan jalankan:');
        console.error('ALTER TABLE public.barang DISABLE ROW LEVEL SECURITY;');
      } else if (error.code === '42P01') {
        console.error('\n🚨 DIAGNOSIS MASALAH:');
        console.error('Tabel "barang" belum dibuat di database Supabase.');
        console.error('Solusi: Buka Supabase SQL Editor dan jalankan skema dari database/schema.sql');
      }
      return;
    }

    console.log('✅ KONEKSI BERHASIL! Supabase merespons dengan normal.');
    console.log(`📊 Jumlah data pada tabel: ${count ?? (data ? data.length : 0)}`);

    if (data && data.length > 0) {
      console.log('📦 Sample data barang:');
      console.log(JSON.stringify(data[0], null, 2));
    } else {
      console.log('\n💡 Data barang kosong [].');
      console.log('Jika Anda yakin tabel sudah diisi data tetapi mengembalikan array kosong,');
      console.log('pastikan RLS mengizinkan SELECT publik atau jalankan database/allow_public_read_barang.sql.');
    }
  } catch (err) {
    console.error('💥 Pengecualian sistem/jaringan:');
    console.error(err);
  }
}

testConnection();
