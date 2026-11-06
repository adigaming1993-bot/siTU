import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

test('1. Role & Jabatan: Verifikasi Form Kelola Akun & Login Check', () => {
  const html = readFileSync('index.html', 'utf8');

  // Hanya 2 pilihan role
  assert.ok(html.includes('<option value="Staf">Staf</option>'), 'Opsi Staf harus ada');
  assert.ok(
    html.includes('<option value="Kepala Sub Bagian Tata Usaha dan Rumah Tangga">Kepala Sub Bagian Tata Usaha dan Rumah Tangga</option>'),
    'Opsi Kepala Sub Bagian Tata Usaha dan Rumah Tangga harus ada'
  );
  assert.ok(!html.includes('<option value="staf_gudang">'), 'Opsi staf_gudang lama tidak boleh ada di select');
  assert.ok(!html.includes('<option value="kepala_tu">'), 'Opsi kepala_tu lama tidak boleh ada di select');

  // Auto-fill jabatan listener
  assert.ok(html.includes("inputUserRoleEl.addEventListener('change'"), 'Event listener change untuk role harus ada');
  assert.ok(html.includes("inputUserJabatanEl.value = 'Kepala Sub Bagian Tata Usaha dan Rumah Tangga'"), 'Auto-fill jabatan kepala harus ada');
  assert.ok(html.includes("inputUserJabatanEl.value = 'Staf'"), 'Auto-fill jabatan staf harus ada');

  // Pengecekan login mengizinkan kedua role
  assert.match(html, /kepala sub bagian tata usaha dan rumah tangga/i, 'Role Kepala Sub Bagian TU dan RT harus diizinkan');
});

test('2. Kop Surat Cetak Laporan: Layout 3 Kolom & Logo Resmi', () => {
  const html = readFileSync('index.html', 'utf8');

  // File logo sidoarjo harus ada
  assert.ok(existsSync('logo-sidoarjo.png'), 'logo-sidoarjo.png harus ada di root');
  assert.ok(existsSync('logo-rsud.png'), 'logo-rsud.png harus ada di root');

  // Layout 3 kolom
  assert.ok(
    html.includes('flex items-center justify-between border-b-4 border-double border-black pb-3 mb-4'),
    'Header kop surat harus menggunakan layout 3 kolom dengan border-b-4 border-double border-black'
  );

  // Logo kiri: logo-sidoarjo.png (75x85)
  assert.ok(html.includes('logo-sidoarjo.png'), 'logo-sidoarjo.png harus dipanggil di kop');
  assert.match(html, /width:\s*75px;\s*height:\s*85px/i, 'Logo sidoarjo harus berukuran 75x85px');

  // Logo kanan: logo-rsud.png (80x80)
  assert.ok(html.includes('logo-rsud.png'), 'logo-rsud.png harus dipanggil di kop');
  assert.match(html, /width:\s*80px;\s*height:\s*80px/i, 'Logo RSUD harus berukuran 80x80px');

  // Teks kop tengah
  assert.ok(html.includes('PEMERINTAH KABUPATEN SIDOARJO'), 'Baris 1 harus ada');
  assert.ok(html.includes('RUMAH SAKIT UMUM DAERAH'), 'Baris 2 harus ada');
  assert.ok(html.includes('R.T. NOTOPURO SIDOARJO'), 'Baris 3 harus ada');
  assert.ok(html.includes('Jalan Mojopahit No. 667, Sidoarjo, Jawa Timur 61215'), 'Baris 4 harus ada');
  assert.ok(html.includes('Telepon (031) 8961649, Laman rsudrtnotopuro.sidoarjokab.go.id,'), 'Baris 5 harus ada');
  assert.ok(html.includes('Pos-el rsudrtnotopuro@sidoarjokab.go.id'), 'Baris 6 harus ada');
});

test('3. Branding SIAPIN: Login Page & Sidebar', () => {
  const html = readFileSync('index.html', 'utf8');

  // Judul SIAPIN dan sub-judul
  assert.ok(html.includes('SIAPIN'), 'Teks SIAPIN harus ada');
  assert.ok(
    html.includes('(Sistem Aplikasi Peminjaman Inventaris)'),
    'Sub-judul (Sistem Aplikasi Peminjaman Inventaris) harus ada'
  );
  assert.ok(!html.includes('Sistem Inventaris Tata Usaha</p>'), 'Teks lama Sistem Inventaris Tata Usaha harus diganti');
});

test('4. Proteksi Akun Terhapus: signOut & Error Merah & Delete Profil', () => {
  const html = readFileSync('index.html', 'utf8');

  const errorMsg = 'Akses Ditolak: Akun Anda telah dihapus atau dinonaktifkan dari sistem.';
  assert.ok(html.includes(errorMsg), 'Pesan error blokir akun harus persis');
  assert.ok(html.includes('supabaseClient.auth.signOut()'), 'signOut harus dipanggil');

  // Tombol hapus staf menjalankan DELETE FROM profil_user
  assert.match(html, /\.from\(['"]profil_user['"]\)\s*\.delete\(\)/, 'Hapus akun harus mengeksekusi DELETE FROM profil_user');
});

test('5. Menu Kelola Stok & Modal Pilihan 3 Kondisi Pengembalian', () => {
  const html = readFileSync('index.html', 'utf8');

  // Menu Sidebar Kelola Stok
  assert.ok(html.includes('id="sidebarKelolaStokBtn"'), 'Tombol sidebar Kelola Stok harus ada');
  assert.ok(html.includes('switchView(\'stok\')'), 'Navigasi switchView stok harus ada');
  assert.ok(html.includes('id="kelolaStokContent"'), 'Konten Kelola Stok harus ada');

  // Penyesuaian stok langsung ke database
  assert.ok(html.includes('sesuaikanStokBarang'), 'Fungsi sesuaikanStokBarang harus ada');
  assert.match(html, /\.from\(['"]barang['"]\)\s*\.update\(\{\s*stok:\s*newStok\s*\}\)/, 'Update kolom stok di tabel barang harus ada');

  // Modal 3 Kondisi Pengembalian
  assert.ok(html.includes('id="modalPengembalian"'), 'Modal Pengembalian harus ada');
  assert.ok(html.includes('Kembali Normal'), 'Opsi Kembali Normal harus ada');
  assert.ok(html.includes('Kembali (Barang Rusak)'), 'Opsi Kembali (Barang Rusak) harus ada');
  assert.ok(html.includes('Mutasi / Habis Pakai'), 'Opsi Mutasi / Habis Pakai harus ada');

  // Logic stok pada pengembalian
  assert.ok(html.includes("kondisi === 'Kembali' && barangId"), 'Kembali normal harus menambahkan stok master barang');
});
