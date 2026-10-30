# Sistem Inventaris Barang Logistik Tata Usaha - RSUD dr. R.T. Notopuro

Aplikasi backend serverless berbasis **Node.js**, **Vercel Serverless Functions**, dan **Supabase Database (PostgreSQL)** untuk pengelolaan barang masuk dan keluar pada Bagian Tata Usaha (TU) RSUD dr. R.T. Notopuro Sidoarjo.

---

## 📁 Struktur Direktori Proyek

```text
.
├── api/
│   └── barang.js          # Endpoint Vercel Serverless Function (GET /api/barang)
├── database/
│   └── schema.sql         # Skema database PostgreSQL & kebijakan RLS Supabase
├── lib/
│   └── supabase.js        # Helper inisialisasi client Supabase dengan dukungan JWT/RLS
├── test/
│   └── smoke.test.js      # Pengujian otomatis skema, handler, dan dependensi
├── .env.example           # Template variabel lingkungan Supabase
├── .gitignore             # Berkas pengabaian git (node_modules, .env, .vercel)
├── package.json           # Konfigurasi proyek ES Modules & dependensi
├── vercel.json            # Konfigurasi routing & header CORS Vercel
└── README.md              # Dokumentasi lengkap proyek
```

---

## 📦 Dependensi yang Digunakan

- **`@supabase/supabase-js`**: SDK resmi Supabase untuk query PostgreSQL, autentikasi, dan RLS.
- **`dotenv`**: Manajemen variabel lingkungan untuk mode development lokal.

---

## 🗄️ Skema Database & Row Level Security (RLS)

File skema berada di `database/schema.sql`.

### 1. Entitas Tabel
- **`profil_user`**: Menyimpan profil pegawai TU terhubung ke `auth.users(id)` dengan kolom `role` (`staf_gudang` atau `kepala_tu`), `nip`, `nama_lengkap`, dan `jabatan`.
- **`barang`**: Master katalog logistik TU (`kode_barang`, `nama`, `kategori`, `stok`, `satuan`, `stok_minimum`, `lokasi_rak`, `keterangan`).
- **`mutasi`**: Buku jurnal keluar-masuk barang (`nomor_dokumen`, `barang_id`, `jenis_mutasi` ['masuk'/'keluar'], `jumlah`, `stok_sebelum`, `stok_sesudah`, `unit_tujuan_asal`, `status`, `user_id`, `disetujui_oleh`).

### 2. Otomatisasi Database (Triggers)
- **`proses_mutasi_stok()`**: Secara otomatis menambah atau mengurangi stok barang saat mutasi masuk/keluar dicatat, serta memvalidasi ketersediaan stok agar tidak terjadi stok negatif (`stok < 0`).
- **`set_updated_at()`**: Memperbarui kolom `updated_at` setiap ada perubahan data.
- **`handle_new_user()`**: Sinkronisasi otomatis saat user didaftarkan melalui Supabase Auth ke tabel `profil_user`.

### 3. Matriks Hak Akses RLS (Row Level Security)

| Tabel | Aksi | Hak Akses Staf Gudang | Hak Akses Kepala TU |
| :--- | :--- | :--- | :--- |
| **`profil_user`** | SELECT | Melihat seluruh profil staf aktif | Melihat seluruh profil staf |
| | UPDATE | Hanya profil sendiri (tidak bisa ubah role) | Semua profil (berwenang ubah role) |
| | DELETE | Ditolak | Diizinkan |
| **`barang`** | SELECT | Melihat seluruh katalog barang | Melihat seluruh katalog barang |
| | INSERT | Menambah barang baru | Menambah barang baru |
| | UPDATE | Mengubah data barang / stok | Mengubah data barang / stok |
| | DELETE | **Ditolak** (mencegah kehilangan data sepihak) | **Diizinkan** (otoritas penghapusan master) |
| **`mutasi`** | SELECT | Melihat seluruh mutasi operasional | Melihat seluruh mutasi & audit trail |
| | INSERT | Mencatat mutasi masuk & keluar | Mencatat mutasi |
| | UPDATE | Hanya transaksi status `draft` miliknya | Verifikasi / persetujuan status mutasi |
| | DELETE | Hanya transaksi status `draft` miliknya | Membatalkan draft / transaksi ditolak |

---

## 🚀 Panduan Setup & Penggunaan

### 1. Persiapan Database di Supabase
1. Buat proyek baru di [Supabase Dashboard](https://supabase.com).
2. Buka menu **SQL Editor**.
3. Salin seluruh isi berkas `database/schema.sql` dan jalankan (*Run*). Skema tabel, trigger kalkulasi stok, data awal (*seed*), dan seluruh kebijakan RLS akan aktif.

### 2. Konfigurasi Variabel Lingkungan
Salin file template `.env.example` menjadi `.env`:
```bash
cp .env.example .env
```
Isi nilai variabel dari Supabase (*Project Settings -> API*):
```env
SUPABASE_URL=https://<project-id>.supabase.co
SUPABASE_ANON_KEY=<anon-public-key>
```

### 3. Pengujian Lokal
Jalankan tes verifikasi sistem:
```bash
npm test
```

---

## 📡 Dokumentasi Endpoint Serverless: `/api/barang`

Mengambil daftar master barang logistik dari Supabase. Mendukung pencarian, filter kategori, restock alert, serta paginasi.

- **Metode**: `GET`
- **URL**: `/api/barang`
- **Header Opsional**:
  - `Authorization: Bearer <jwt-token>` (mengaktifkan evaluasi RLS spesifik pengguna yang login).

### Parameter Query:
- `kategori`: Menyaring berdasarkan kategori (misal: `?kategori=Alat Tulis Kantor`)
- `search` / `q`: Pencarian kata kunci pada nama atau kode barang (misal: `?search=Kertas`)
- `stok_kritis`: Bernilai `true` untuk memfilter barang yang stoknya `<= stok_minimum`
- `limit`: Jumlah data per halaman (default: `50`, maks: `100`)
- `offset`: Offset untuk paginasi (default: `0`)
- `sort`: Kolom pengurutan (`nama`, `kode_barang`, `kategori`, `stok`, `created_at`)
- `order`: Arah pengurutan (`asc` atau `desc`, default: `asc`)

### Contoh Respon Sukses (200 OK):
```json
{
  "success": true,
  "instansi": "RSUD dr. R.T. Notopuro Sidoarjo - Bagian Tata Usaha",
  "message": "Berhasil mengambil daftar barang logistik.",
  "meta": {
    "total": 7,
    "limit": 50,
    "offset": 0,
    "count": 7
  },
  "data": [
    {
      "id": "e44dcfb6-7140-4107-b248-18e47455d315",
      "kode_barang": "TU-ATK-001",
      "nama": "Kertas HVS A4 75 GSM",
      "kategori": "Alat Tulis Kantor",
      "stok": 150,
      "satuan": "rim",
      "stok_minimum": 20,
      "lokasi_rak": "Rak A-1 Logistik TU",
      "keterangan": "Pengadaan rutin untuk administrasi rumah sakit",
      "created_at": "2026-10-30T08:00:00Z",
      "updated_at": "2026-10-30T08:00:00Z"
    }
  ]
}
```

---

## ☁️ Deployment ke Vercel

### Menggunakan Vercel CLI:
```bash
npm i -g vercel
vercel login
vercel
```

### Mengatur Environment Variables di Vercel:
Tambahkan nilai kredensial Supabase pada dashboard Vercel (*Project Settings -> Environment Variables*):
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Setelah dideploy, endpoint dapat langsung diakses di:
`https://<project-anda>.vercel.app/api/barang`
