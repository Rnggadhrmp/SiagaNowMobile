# Status Implementasi — Penyempurnaan Visual SiagaNow

Catatan ini melengkapi dan tidak menggantikan riwayat terdahulu di `IMPLEMENTATION_PROGRESS.md` dan `IMPLEMENTATION_STATUS.md`.

## Tahap 1 — Audit Figma, aset, dan kode aktif

**Tanggal/waktu:** 16 November 2026, 08:55 WIB (Asia/Bangkok)

- **Project aktif:** repository Flutter `C:\College\SiagaNowMobile`; perubahan hanya diarahkan ke repository mobile ini.
- **Frame Figma ditinjau:** Beranda, Berita, Cuaca, Laporkan Bencana, Rute Evakuasi, Layanan Darurat/Keluarga Siaga, Kontak Darurat, Profil, dan Status Laporan.
- **File yang diubah pada tahap ini:** `STATUS_IMPLEMENTASI.md`.
- **Temuan visual:** aset `header_waves.png` dan `landscape_background.png` sudah tersedia. Figma menggunakan gelombang atas dan footer lanskap pada sebagian besar frame yang ditinjau, sementara implementasi latar masih tersebar pada Beranda, Profil, layar sukses, dan Intro.
- **Temuan interaksi:** layar peta menggunakan data shelter dari API; belum ada fixture shelter lokal terpisah. Loading beberapa layar masih menggunakan spinner, dan navigasi rute masih memakai transisi default Flutter.
- **Aset:** tidak ada aset gambar baru yang dibutuhkan untuk latar global. Aset centang dan pin Figma yang ditambahkan pada pekerjaan sebelumnya tetap dipertahankan.
- **Pengujian:** belum dijalankan pada tahap audit.
- **Kendala:** frame mockup menunjukkan status bar iPhone, sedangkan target adalah Android; posisi header harus menyesuaikan inset sistem tanpa memotong gelombang.
- **Belum selesai:** global background, shelter simulasi lokal, motion/skeleton, integrasi seluruh halaman, dan QA visual emulator.

## Tahap 2 — Global background dan header

**Tanggal/waktu:** 16 November 2026, 09:06 ICT (Asia/Bangkok)

- **Halaman:** tab Beranda, Peta Evakuasi, Form Laporan, Berita, Layanan, Cuaca, Donasi, Kontak Darurat, Keluarga Siaga, Penilaian Risiko, Detail Berita, Detail Laporan, Riwayat, Profil, dan status sukses.
- **File diubah:** `lib/main.dart`.
- **Perubahan visual:** menambahkan `SiagaNowHeaderBackground` dengan aset gelombang pada rasio fit-width, gradient mint-hijau, dan wave overlay transparan. `SiagaNowPageBackground` menempatkan lanskap/danau/pepohonan di belakang konten dengan overlay mint agar teks tetap terbaca. Latar bawah kini dipakai oleh tab utama dan layar turunan; gambar dekoratif duplikat di layar layanan dihapus.
- **Aset:** memakai ulang `assets/images/header_waves.png` dan `assets/images/landscape_background.png`; tidak menambah aset bitmap.
- **Logika/interaksi:** struktur peta, kamera, formulir, dan navigasi dipertahankan di atas lapisan latar. Header app bar internal menggunakan widget yang sama.
- **Pengujian:** `flutter analyze --no-pub` lulus pada 09:06 ICT. Test suite dan build belum dijalankan untuk tahap ini.
- **Kendala:** peta tetap membutuhkan tile jaringan/cache sendiri dan sengaja berada di atas gambar lanskap.
- **Belum selesai:** QA emulator, tahap motion/loading, dan uji konfigurasi fixture shelter.

## Tahap 3 — Status laporan dan sukses tersimpan

**Tanggal/waktu:** 16 November 2026, 09:06 ICT (Asia/Bangkok)

- **Halaman:** Status Laporan.
- **File diubah:** `lib/main.dart`.
- **Perubahan visual:** gelombang diganti dengan widget header proporsional; ruang awal konten diperkecil agar ikon centang tidak tampak turun/terpotong; jarak kartu shelter dan tombol bawah diseimbangkan.
- **Logika/interaksi:** halaman sukses tetap hanya dibuka setelah respons API berisi data laporan dan ID yang valid. Animasi centang singkat menghormati Reduce Motion. Rekomendasi shelter fixture hanya mungkin dalam mode debug khusus dan akan bertanda `SHELTER SIMULASI` dengan jarak perkiraan.
- **Aset:** memakai ulang SVG centang dan pin Figma yang sebelumnya sudah ada.
- **Pengujian:** analyzer lulus; uji widget dan pemeriksaan layar emulator menyusul.
- **Kendala:** rekomendasi shelter resmi tetap berasal dari respons server yang terverifikasi; fixture lokal tidak menggantikan rekomendasi server.
- **Belum selesai:** uji submit sukses/gagal, snapshot visual, dan QA perangkat.

## Tahap 4 — Shelter simulasi lokal

**Tanggal/waktu:** 16 November 2026, 09:07 ICT (Asia/Bangkok)

- **Halaman:** Peta Evakuasi, hasil sukses laporan dalam mode QA.
- **File diubah:** `lib/main.dart`.
- **Logika/interaksi:** tiga fixture lokal untuk Kuranji, Pauh, dan Koto Tangah ditandai `simulation: true`, `source: Fixture lokal SiagaNow`, dan alamat menyebut titik latihan. Fixture tidak memakai kapasitas atau status operasional yang direka. Fixture hanya dimasukkan ke tampilan ketika build debug memakai `--dart-define=SIAGANOW_SHELTER_SIMULATION=true`; tidak menjadi request backend dan tidak mengubah kontrak/API atau repository Laravel.
- **Perubahan visual:** banner amber menjelaskan mode uji; marker simulasi amber dan setiap kartu menyebut “Shelter Simulasi · titik latihan, bukan lokasi resmi”. Bottom sheet menyatakan kapasitas/status tidak tersedia. Jika API gagal, error API tetap ditampilkan walaupun daftar fixture muncul.
- **Rekomendasi:** setelah server mengonfirmasi laporan tersimpan, mode QA dapat memilih fixture koordinat terdekat dan menampilkan jarak perkiraan dengan label simulasi. Respons API simulasi/yang tidak terverifikasi tetap tidak dianggap rekomendasi resmi.
- **Aset:** tidak ada aset tambahan.
- **Pengujian:** model shelter dan kontrak laporan sudah tercakup test yang ada; pemeriksaan fixture visual pada emulator masih menunggu APK build.
- **Kendala:** koordinat fixture adalah titik latihan perkiraan; tidak boleh dipakai navigasi atau disamakan dengan shelter resmi.
- **Belum selesai:** build debug khusus QA, pemeriksaan marker dan status sukses, lalu build/debug QA umum.

## Tahap 5 — Motion dan loading

**Tanggal/waktu:** 16 November 2026, 09:07 ICT (Asia/Bangkok)

- **File diubah:** `lib/main.dart`.
- **Perubahan interaksi:** tema memakai gabungan fade/slide 2.5% selama transisi rute, durasi mengikuti transisi Material, curve easeInOutCubic, dan transisi dimatikan saat Reduce Motion aktif. Bottom navigation tetap memakai animasi bawaan tanpa membuat ulang tab. Auth sheet mendapat blur ringan; ikon sukses mendapat pop singkat yang menghormati Reduce Motion.
- **Loading:** skeleton layout lembut untuk Home, Profil, Berita, Shelter, Riwayat Laporan, Keluarga Siaga, dan Penilaian Risiko. Error dan empty state tetap menggunakan jalur yang ada.
- **Pengujian:** `flutter analyze --no-pub` lulus; `flutter test --no-pub` lulus (33 test).
- **Kendala:** shimmer dibuat satu kali dan berhenti agar tidak terus memakan frame atau mengunci `pumpAndSettle`.
- **Belum selesai:** visual emulator, pemeriksaan frame/overflow, dan APK debug.

## Tahap 6 — Integrasi seluruh halaman

**Tanggal/waktu:** 16 November 2026, 09:07 ICT (Asia/Bangkok)

- **Halaman:** seluruh tab utama dan layar turunan mobile yang memakai AppBar/latar ilustratif; intro onboarding yang memiliki komposisi khusus dipertahankan.
- **File diubah:** `lib/main.dart`.
- **Perubahan visual:** background bawah berada di belakang semua tab utama; halaman detail, cuaca, kontak, risiko, keluarga, donasi, profil, riwayat, serta sukses memakai header/lanskap global sesuai komposisi layarnya. Peta dan form tetap memiliki layer interaktif sendiri.
- **Pengujian:** analyzer lulus; 33 test lulus. Pembangunan APK dan pemeriksaan emulator masih berjalan.
- **Aset:** menggunakan ulang aset wave/lanskap dan ikon laporan Figma yang sudah berada dalam project.
- **Kendala:** belum ada screenshot emulator setelah integrasi pada tahap ini.
- **Belum selesai:** build, install/launch emulator, memeriksa sedikitnya Beranda, Peta, Form, Profil, Berita, Cuaca, Keluarga, dan Status Laporan; catat hasil akhir.

## Tahap 7 — QA emulator dan APK

**Tanggal/waktu:** 16 November 2026, 09:20 ICT (Asia/Bangkok)

- **Build:** `flutter build apk --debug --dart-define=SIAGANOW_SHELTER_SIMULATION=true` berhasil. APK QA: `build/app/outputs/flutter-apk/app-debug.apk` (228,868,752 byte). Flag fixture opt-in aktif di build debug ini; build release tidak dapat menampilkan fixture karena pemeriksaan `kDebugMode`.
- **Pemeriksaan emulator:** APK terpasang dan diluncurkan pada emulator `emulator-5554`. Beranda, Peta dengan marker latihan amber di Padang, Form Laporan, Berita, Layanan, Profil, dan Keluarga Siaga diperiksa. Peta mode QA tetap di Padang; penggunaan GPS normal tidak berubah.
- **Temuan visual dan koreksi:** gelombang header awalnya terpotong pada toolbar; tinggi toolbar disamakan dengan rasio aset sehingga gelombang tampak utuh. Peta QA awalnya berpindah ke GPS sintetis emulator; mode fixture sekarang tetap di titik default Padang. Pemeriksaan Keluarga Siaga menemukan gelombang body duplikat di bawah AppBar; lapisan duplikat dihapus.
- **Status sukses:** belum bisa dijalankan end-to-end pada emulator karena memerlukan pengiriman laporan yang dikonfirmasi backend. Kondisi tetap diuji dengan widget test layar sukses pada ukuran 360×740, termasuk label fixture, jarak, tombol, dan overflow.
- **Hasil pemeriksaan:** `flutter analyze --no-pub` lulus tanpa temuan; `flutter test --no-pub` lulus, 35 test; build APK debug berhasil; `git diff --check` bersih. Log build memberi peringatan kompatibilitas KGP plugin `flutter_timezone` untuk perubahan Flutter mendatang, tetapi build saat ini berhasil.
- **Screenshot QA:** artefak di `artifacts/qa/` berisi screenshot Beranda, Peta, Form, Berita, Layanan, kartu Cuaca Beranda, dan Detail Cuaca. Profil/Keluarga juga diperiksa; screenshot-nya dibuang karena menampilkan data akun pribadi pada emulator.
- **Kendala tersisa:** belum ada konfirmasi laporan nyata dari backend sehingga halaman sukses tidak dipicu langsung pada emulator; layar tersebut diuji dengan widget test. Kartu Cuaca Beranda dan rute detail Cuaca kini sudah diperiksa di emulator.
- **Pekerjaan tersisa:** tidak ada perubahan backend atau data produksi. Jalankan ulang aplikasi dengan flag di atas hanya saat ingin menguji fixture; matikan flag atau gunakan build debug biasa untuk menyembunyikannya.

## Tahap 8 — Audit final glass navigation dan shelter tunggal

**Tanggal/waktu:** 16 November 2026, 09:51 ICT (Asia/Bangkok)

- **Brief baru:** menekankan glass navigation yang mengambang di atas lanskap, tab transition nyata tanpa menghilangkan state, shimmer bergerak, dan satu fixture shelter lokal.
- **Audit kode:** nav saat ini masih NavigationBar buram di bawah body; `extendBody` belum aktif; tab menggunakan IndexedStack tanpa transisi; skeleton hanya memudar sekali; fixture lokal masih berjumlah tiga.
- **Perencanaan perubahan:** ganti navigasi menjadi overlay frosted glass, panjangkan background body ke belakangnya, pertahankan widget tab sambil menganimasikan opacity/slide, ubah skeleton menjadi shimmer saat loading, dan ganti data lokal menjadi satu Shelter Simulasi SiagaNow dengan ID/koordinat eksplisit, jarak GPS, fallback, serta tautan arah.
- **File sasaran:** `lib/main.dart`, test Flutter terkait, dan file status ini. Tidak ada perubahan backend.
- **Implementasi:** glass nav floating memakai `BackdropFilter`, permukaan 79% opak (sekitar 21% transparan), border ringan, radius 26, dan indikator mint bergerak. `extendBody: true` menjaga lanskap mengalir ke belakang nav. Navigasi tab menggunakan opacity/slide 320 ms dan mempertahankan subtree tab.
- **Motion/loading:** skeleton kini memiliki shimmer yang terus bergerak selama loading dan berhenti mengikuti Reduce Motion. Blur modal yang ada dipertahankan.
- **Shelter lokal:** fixture tunggal kini bernama `Shelter Simulasi SiagaNow`, ID `siaganow-sim-kuranji-001`, koordinat latihan `-0.9138, 100.3974`, dan label `SIMULASI — BUKAN SHELTER RESMI`. Daftar/detail memakai jarak garis lurus hanya dengan GPS; detail memberi fallback izin/lokasi dan tautan Google Maps dengan koordinat yang sama tanpa estimasi waktu.
- **File:** `lib/main.dart`, `test/api_models_test.dart`, dan `STATUS_IMPLEMENTASI.md`.
- **Aset:** tidak ada aset tambahan; pakai ulang latar header/lanskap.
- **Validasi awal:** `flutter analyze --no-pub` lulus; test dan QA emulator untuk nav kaca/marker tunggal/build baru menyusul.
- **Belum selesai:** validasi overlay pada perangkat, memastikan scroll terakhir tidak tertutup nav, menjalankan ulang seluruh test dan membangun APK debug terbaru.

## Tahap 9 — QA visual glass nav dan fixture tunggal

**Tanggal/waktu:** 16 November 2026, 10:00 ICT (Asia/Bangkok)

- **QA emulator:** APK tahap baru sudah dipasang pada `emulator-5554`. Screenshot Beranda memperlihatkan shimmer aktif dan glass nav transparan di atas pegunungan; screenshot Peta memperlihatkan nav kaca melayang, indikator tab mint, serta background berlanjut di belakang panel.
- **Temuan:** Peta memperlihatkan tiga marker amber karena dua data simulasi API lama tampil bersama fixture lokal yang baru. `ShelterRecord.fromJson` kini juga mengenali metadata simulasi per record; dalam mode fixture tunggal, simulasi dari respons API disisihkan dari tampilan supaya hanya satu fixture lokal tampil. Data non-simulasi API tetap dipertahankan.
- **File yang diubah pada koreksi:** `lib/main.dart`.
- **Pengujian/build setelah koreksi filter:** masih menunggu; jalankan analyzer/test/build dan pasang APK ulang sebelum menutup tahap.

## Tahap 9 — QA visual glass nav dan fixture tunggal (selesai)

**Tanggal/waktu:** 16 November 2026, 10:03 ICT (Asia/Bangkok)

- **Build final:** `flutter build apk --debug --dart-define=SIAGANOW_SHELTER_SIMULATION=true` berhasil; APK `build/app/outputs/flutter-apk/app-debug.apk` (228,880,592 byte, 10:01 ICT). APK koreksi filter sudah dipasang ulang pada emulator `emulator-5554`.
- **Validasi kode:** `flutter analyze --no-pub` lulus tanpa temuan; `flutter test --no-pub` lulus, 36 test; `git diff --check` bersih.
- **QA visual:** Beranda menunjukkan shimmer saat memuat dan glass nav melayang di atas ilustrasi. Peta menunjukkan satu marker amber lokal, banner simulasi, nav kaca transparan, dan lanskap terlihat menerus di belakang nav. Screenshot final tersedia di `artifacts/qa/glass-home.png` dan `artifacts/qa/glass-map-single.png`; tangkapan detail shelter ada di `artifacts/qa/shelter-detail.png`.
- **Perbaikan berdasarkan QA:** simulasi dari respons API tidak lagi muncul bersama fixture lokal dalam mode fixture tunggal; respons API non-simulasi tetap dipertahankan. Jarak menggunakan GPS jika tersedia, fallback menyatakan jarak belum tersedia, dan tombol arah eksternal memakai koordinat fixture yang sama. Tidak ada estimasi waktu/perjalanan atau kapasitas/status shelter yang direka.
- **Batas QA:** status sukses laporan tidak dikirim ke backend pada emulator; alur sukses tetap tercakup test widget. Detail fixture menampilkan ID, koordinat, label bukan shelter resmi, jarak/fallback, dan tautan arah sebagaimana implementasi.
- **Catatan build:** Gradle mengeluarkan peringatan kompatibilitas Kotlin Gradle Plugin dari dependency `flutter_timezone` untuk perubahan Flutter mendatang; build debug saat ini berhasil.
- **Status:** implementasi dan pemeriksaan brief selesai. Fixture hanya muncul pada build debug yang secara eksplisit memakai `SIAGANOW_SHELTER_SIMULATION=true`.

## Tahap 10 — Gradient global, kartu translucent, dan radius (selesai)

**Tanggal/waktu:** 16 November 2026, 10:55 ICT (Asia/Bangkok)

- **Aset referensi:** gambar gradient yang diberikan pengguna disalin ke `assets/images/global_color_overlay.png` (353,396 byte). Folder `assets/images/` sudah terdaftar di `pubspec.yaml`, jadi aset baru otomatis ikut bundle; sumber dicatat sebagai referensi dari pengguna.
- **Overlay global:** layer memakai opacity `0.30` (30%) di atas background utama, dengan gambar gradient tetap terpisah dari ilustrasi lanskap/wave. Dipasang pada header dan `SiagaNowPageBackground`; onboarding, profil, dan layar Status Laporan yang memakai komposisi latar khusus juga mendapat overlay. Ilustrasi dan tile peta tetap berada di lapisan yang benar.
- **Permukaan informasi:** token reusable `SiagaNowSurfaceTokens` menerapkan putih/mint dengan alpha `0xBF` (sekitar 75% opak) ke kartu umum, cuaca, statistik, prakiraan, AI Flood Detection, empty state, informasi shelter, dan kartu laporan. Peringatan/error dan notice amber memakai alpha `0xCC` (80% opak). Dialog dan bottom sheet memakai alpha `0xC7` (78% opak). Input, tombol, badge, kartu berita berfoto, dan blok brand yang memang perlu solid dipertahankan.
- **Radius:** kartu/panel standar 12 px; panel info khusus 12–14 px; dialog/bottom sheet 16 px; input/tombol 12 px. Radius besar yang dekoratif dipertahankan hanya pada indikator/tab atau ilustrasi khusus. Blur tidak ditambahkan ke setiap kartu; blur tetap selektif pada modal yang sudah ada.
- **Cakupan:** Beranda, Peta, Laporan, Berita, Layanan, onboarding, Status Laporan, Profil, Cuaca, Keluarga Siaga, Riwayat, Penilaian Risiko, detail Berita/Laporan/Cuaca, Kontak Darurat, Donasi, Shelter, dan halaman terkait yang memakai background bersama.
- **QA emulator:** APK debug final terpasang. Screenshot Beranda memperlihatkan tone gradient baru di atas gelombang/lanskap, kartu AI dan peringatan translucent dengan teks terbaca, serta kontrol tetap solid. Screenshot Peta memperlihatkan tile dan kontrol tetap tajam, panel shelter translucent, dan background terlihat di sekeliling map. Artefak: `artifacts/qa/global-overlay-final.png` dan `artifacts/qa/global-overlay-map.png`.
- **Validasi akhir:** `flutter analyze --no-pub` lulus tanpa temuan; `flutter test --no-pub` lulus (35 test); `flutter build apk --debug` berhasil; `git diff --check` bersih. APK ada di `build/app/outputs/flutter-apk/app-debug.apk` dan sudah dipasang di emulator.
- **Catatan:** Gradle tetap mengeluarkan peringatan migrasi Kotlin Gradle Plugin dari dependency `flutter_timezone`; build saat ini berhasil. Status sukses laporan tetap tidak dikirim ke backend pada emulator; alur layout terkait tercakup test yang ada.
## Tahap 11 — Fixed background Profil dan audit YOLO

**Tanggal:** 16 November 2026

- **Profil:** komposisi Stack sudah memisahkan gradient/header/wave tetap dari ListView; background tetap di belakang konten. Test widget ditambahkan untuk mengukur posisi sebelum dan sesudah scroll serta memastikan menu bawah muncul.
- **Audit model:** tidak ditemukan file weights `.pt`/`.onnx`, dataset, class map, script training/inference, atau service YOLO pada dua repository. CCTV flood detections tetap fitur terpisah.
- **Dampak:** inference nyata belum aktif dan tidak ada hasil deteksi rekaan. Kelas banjir/longsor/akses jalan/kerusakan bangunan belum diaktifkan.

## Tahap 12 — Fondasi analisis AI laporan

- **Laravel:** migration `report_ai_analyses` menambah status analisis, model/version, deteksi terstruktur, bukti sumber, timestamp, error code, dan status/catatan/verifikator admin. Tidak ada migration destruktif.
- **Upload dan antrean:** laporan API membuat status pending dan tetap menyimpan bukti di private disk. Jika endpoint YOLO diaktifkan dengan URL/token dan ada foto, pekerjaan dikirim ke queue `ai`; video tidak dikirim. Error tidak menghapus laporan atau bukti. Default service disabled sehingga tidak ada job/inference palsu.
- **Kontrak:** interface service menerima gambar privat, menormalisasi kelas, confidence, bounding box 0–1. Contoh contract dijelaskan di `docs/YOLO_REPORT_ANALYSIS.md` dan bukan hasil nyata.
- **Admin:** detail laporan menampilkan status analisis, model/waktu, kelas/confidence/bbox, bukti foto via route privat, dan verifikasi di bawah permission `reports.manage`. Catatan audit dibuat; verifikasi tidak mengubah status laporan resmi dan tidak mengirim peringatan.
- **Flutter:** status analisis/verifikasi tampil di sukses, riwayat, dan detail. Mobile hanya menerima status, bukan hasil deteksi.
- **Konfigurasi:** `YOLO_REPORT_ENABLED=false` secara default. URL dan token disimpan di environment server. Nyalakan hanya setelah service model nyata, worker `ai`, dan tes end-to-end tersedia.
- **Belum tersedia:** model tervalidasi, dataset berlabel, daftar kelas/evaluasi, endpoint inference, worker operasional, dan notifikasi wilayah. Tidak ada peringatan dini otomatis.
- **Verifikasi akhir:** `flutter analyze --no-pub` lulus; `flutter test --no-pub` lulus (37 test), termasuk scroll test yang mengukur posisi gradient tetap; `flutter build apk --debug` berhasil. Laravel `php artisan test` lulus (52 test, 323 assertions), termasuk service contract, pending status, dan admin verification; Pint lulus untuk file PHP yang berubah. `git diff --check` bersih (hanya peringatan Git normalisasi CRLF pada beberapa file Laravel). APK: `build/app/outputs/flutter-apk/app-debug.apk`.

## Ringkasan akhir — fixed background Profil dan YOLO

- **Sudah berfungsi:** background Profil tetap diam saat daftar menu digulir; test widget membandingkan posisi gradient sebelum dan sesudah scroll. Status analisis dan verifikasi admin tampil pada layar sukses, riwayat, dan detail laporan.
- **Fondasi YOLO:** Laravel menyimpan siklus `pending/processing/completed/failed`, mengirim foto ke queue hanya bila endpoint dikonfigurasi, menyimpan hasil terstruktur, dan menyediakan pemeriksaan admin dengan audit. Bukti tetap privat. Verifikasi AI tidak mengubah status laporan resmi dan tidak mengirim peringatan.
- **Belum aktif:** tidak ditemukan weights/model, dataset, class map, atau service inferensi. Karena itu belum ada deteksi bencana nyata; `YOLO_REPORT_ENABLED` tetap `false` secara default. Video belum didukung analisis gambar.
- **Masih diperlukan:** model dan dataset tervalidasi beserta kelas/evaluasinya, endpoint YOLO privat, worker queue operasional, lalu uji end-to-end dengan bukti berlabel. Peringatan resmi tetap memerlukan keputusan admin.
- **Validasi:** Flutter analyzer bersih, 37 test Flutter lulus, APK debug berhasil dibangun; 52 test Laravel (323 assertions) lulus, Pint dan pemeriksaan diff bersih.

## Tahap 13 — Perbaikan global header dan scroll (selesai)

**Tanggal:** 16 November 2026

- **Bug dan penyebab:** `_SoftHeaderWave` menggambar shape transparan terpisah di bawah `header_waves.png`, sehingga garis hijau tampak turun dan terpisah dari gelombang. Layer tint sebelumnya juga berupa overlay global berukuran sendiri, bukan tint yang terikat pada geometri gambar header.
- **Perubahan widget:** `SiagaNowHeaderBackground` tetap menjadi komponen reusable tunggal. Layer sekarang tersusun: gradient dasar → `header_waves.png` → salinan gambar identik yang diberi green tint 50% → foreground. Kedua gambar menggunakan ukuran, posisi, alignment, dan fit yang sama. Opacity menerima nilai konfigurasi namun dibatasi pada 40–60% (default 50%). Shape `_SoftHeaderWave` yang terpisah dihapus.
- **Fixed behavior:** semua AppBar yang diaudit memakai `SiagaNowHeaderBackground` pada `flexibleSpace`, sehingga tetap pinned di atas body scroll. Profil dan Status Laporan memakai Stack dengan dekorasi terpisah dari scrollable content. Bottom navigation glass dan background bawah tidak diubah. Halaman peta full-screen dan onboarding tetap mengikuti layout khususnya.
- **Halaman yang memakai header reusable:** Beranda, Berita, Cuaca/detail, Riwayat/detail laporan, Keluarga Siaga, Penilaian Risiko, Donasi, Kontak Darurat, serta AppBar halaman terkait lainnya. Profil dan Status Laporan memakai header background pada Stack tetap; keduanya juga punya widget test scroll khusus.
- **Widget test:** memeriksa bounds layer wave dan tint sama, opacity 0.5, posisi keduanya tidak berubah setelah scroll, dan kartu foreground bergerak.
- **QA emulator:** APK debug terbaru terpasang di `emulator-5554`. Scroll visual diperiksa di Beranda dan detail Cuaca; header tetap berada di posisi atas. Tab Berita juga diperiksa. Profil dan Status Laporan diverifikasi lewat widget test fixed-background; test Status Laporan memakai konten panjang untuk memastikan scroll terjadi.
- **Screenshot QA:** `artifacts/qa/header-wave-layering.png`, `artifacts/qa/header-home-scrolled.png`, `artifacts/qa/header-news.png`, `artifacts/qa/header-weather-detail.png`, dan `artifacts/qa/header-weather-scrolled.png` (judul dan tombol kembali tetap terlihat).
- **Validasi:** `flutter analyze --no-pub` lulus; `flutter test --no-pub` lulus (39 test); `flutter build apk --debug` berhasil dan APK dipasang pada emulator. Peringatan build KGP `flutter_timezone` tetap muncul, tanpa menggagalkan build.

## Tahap 14 — Koreksi layering khusus Profil (selesai)

**Tanggal:** 16 November 2026

- **Audit route/widget:** Profil dibuka melalui tombol profil pada AppBar utama saat pengguna login, serta menu “Profil dan laporan saya” di halaman Layanan. Keduanya membuat `ProfilePage`. Widget utamanya adalah `ProfilePage` (`StatefulWidget`) dengan `Scaffold` lokal dan `Stack`; profil memakai kontrol kembali/muat ulang sendiri di dalam `SafeArea`, bukan `AppBar` standar.
- **Penyebab spesifik:** Profil sudah memakai `SiagaNowHeaderBackground`, tetapi struktur Stack lokal berbeda dari halaman lain: `Positioned` gradient 280 px berada di belakang wave 112 px, lalu `_SiagaNowColorOverlay` kedua ditempatkan mulai `top: 112` hingga dasar layar. Kombinasi bidang gradient dan overlay badan itu membuat warna persegi terpisah tepat di bawah header. Wave dan tint pada komponen reusable sendiri sudah sejajar.
- **Perubahan:** `ProfilePage` kini memakai satu base color penuh sebagai background utama, mempertahankan landscape/footer wash pada layer dekoratif, lalu memasang `SiagaNowHeaderBackground` fixed setinggi 112 px. Overlay badan profil dan gradient lokal 280 px dihapus. Kontrol kembali/refresh dan ListView tetap pada foreground; data/API, menu, dan navigasi tidak diubah.
- **Struktur lama → baru:** base color + gradient 280 px + header reusable 112 px + overlay global badan + konten → base color + footer dekoratif + satu header reusable dengan wave/tint identik + kontrol dan konten scroll.
- **Pengujian:** widget test memeriksa posisi background/header/wave/overlay sebelum dan setelah scroll, bounds wave/tint yang sama, opacity 50%, dan perubahan posisi menu “Informasi Donasi”. Test Profil khusus lulus.
- **QA emulator:** APK terbaru dipasang. Profil dibuka melalui route profil dan diuji pada posisi atas serta setelah scroll pada viewport ringkas sementara; gelombang/tint tetap, isi profil bergerak di depannya, dan tombol kembali/refresh tetap terlihat. Ukuran emulator dikembalikan setelah pemeriksaan. Screenshot layar penuh tidak disimpan karena memuat nama, email, nomor telepon, dan alamat akun. Pemeriksaan visual dilakukan langsung pada emulator.
- **Catatan lingkungan:** selama QA emulator tampil pesan backend bahwa tabel `report_ai_analyses` belum ada pada database lokal. Itu terkait migration YOLO sebelumnya, bukan layering Profil; endpoint/database tidak diubah pada tahap ini.
- **Validasi:** `flutter analyze --no-pub` lulus; seluruh `flutter test --no-pub` lulus (39 test); `flutter build apk --debug` berhasil dan APK terbaru terpasang; `git diff --check` bersih.

## Tahap 15 — Header Profil mengikuti Beranda (selesai)

**Tanggal:** 16 November 2026

- **Perubahan pendekatan:** mengganti susunan fixed background penuh Profil pada tahap 14 dengan layout halaman standar. `Scaffold.appBar` kini menampilkan header di bagian atas, sedangkan body profil menjadi area terpisah yang discroll normal. Tahap 15 menggantikan pendekatan fixed-background Profil yang dicatat pada tahap 14.
- **Widget/header:** `ProfilePage` memakai komponen reusable `SiagaNowHeaderBackground` yang sama dengan Beranda di `AppBar.flexibleSpace`. Tingginya 92 px, sama dengan toolbar Beranda; komponen tetap menggambar wave dan tint hijau 50% pada geometri yang sama. AppBar Profil menyediakan tombol kembali dan muat ulang. Konten memakai `ColoredBox` lalu `_buildProfileContent`/`ListView`; tidak ada Stack dekoratif fixed, wave lokal kedua, atau overlay yang memanjang di belakang isi.
- **Perbandingan visual:** screenshot emulator Beranda yang sudah ada (`artifacts/qa/header-home-scrolled.png`) dan pemeriksaan langsung Profil menunjukkan wave, tint, dan tinggi header yang konsisten. Perbedaannya hanya kontrol header (Beranda menampilkan identitas/akses profil; Profil menampilkan kembali/refresh) dan konten layar. Pada Profil, avatar boleh melewati batas bawah header; kartu dan menu tetap tampil di atas body dan bergerak normal saat discroll, sementara AppBar tetap di atas.
- **Fungsi dipertahankan:** pemuatan API dan data profil dinamis, edit, navigasi, menu, logout, serta bottom navigation glass tidak diubah.
- **File yang diubah:** `lib/main.dart` dan `test/feature_lifecycle_layout_test.dart`. Test layout memeriksa AppBar standar 92 px, kesamaan bounds wave/tint dan opacity 0.5, serta scroll menu di body sementara header tetap pada posisinya.
- **Bukti visual:** layar Profil sudah dibuka dari navigasi aplikasi pada emulator setelah APK terbaru dipasang dan diperiksa pada posisi atas serta setelah scroll. Screenshot Profil tidak disimpan karena menampilkan nama, email, nomor telepon, dan alamat akun. Screenshot Beranda tanpa data tersebut tetap tersedia sebagai pembanding.
- **Validasi:** `flutter analyze --no-pub` lulus; `flutter test --no-pub` lulus (39 test); `flutter build apk --debug` berhasil dan APK terbaru dipasang pada emulator. `git diff --check` bersih. Build masih menampilkan peringatan kompatibilitas Kotlin Gradle Plugin dari dependency `flutter_timezone`, tetapi sukses.
- **Catatan lingkungan:** saat membuka Profil, API lokal menampilkan pesan bahwa tabel `report_ai_analyses` belum tersedia pada database lokal. Ini tidak terkait perubahan header dan tidak diubah karena cakupan tugas ini tidak menyentuh backend/database.

## Tahap 16 — Kontras Profil dan foto profil (implementasi; QA emulator tertunda)

**Tanggal:** 16 November 2026

- **Latar Profil:** body Profil memakai gradient vertikal halus dari `#24785D` (100% opacity) ke `#479979`, `#9BD0B4`, lalu warna halaman `#CDEBDD`. Header AppBar, gambar gelombang, tint hijau 50%, serta posisi tombol kembali dan refresh tetap memakai komponen dan geometri yang ada. Kartu informasi tetap putih semi-solid di atas background.
- **Dialog Edit:** background `#FCFFFD` solid dengan surface tint transparan; kontras judul, isi, dan aksi ditingkatkan. Dialog hanya menyatakan data profil server sebagai informasi dan mengelola foto, tidak mengklaim perubahan data akun berhasil.
- **Foto profil:** avatar dan aksi Edit membuka galeri melalui `image_picker`. Foto JPG/JPEG/PNG diperiksa berdasarkan ekstensi, signature, dan keberhasilan decode konten, dibatasi maksimal 10 MB, lalu ditampilkan sebagai preview lingkaran dengan `BoxFit.cover` sebelum disimpan. Pengguna dapat mengganti atau menghapus foto; avatar kembali ke ikon default setelah dihapus. Pembatalan picker tidak mengubah foto tersimpan.
- **Penyimpanan dan backend:** foto disalin ke app-private `Application Support/profile/profile_photo.jpg|png`, sehingga tetap ada setelah halaman/aplikasi dibuka ulang. Penyimpanan hanya di perangkat ini. Pada source mobile di workspace tidak ditemukan endpoint upload foto profil; API profil yang dipakai hanya `GET user`, jadi tidak ada sinkronisasi server yang diklaim. Android menggunakan pemilih foto sistem tanpa permission storage tambahan; deskripsi galeri iOS ditambahkan.
- **File yang diubah:** `lib/main.dart`, `lib/services/profile_photo_service.dart`, `pubspec.yaml`, `pubspec.lock`, `ios/Runner/Info.plist`, `test/profile_photo_service_test.dart`, dan `test/profile_page_photo_test.dart`.
- **Pengujian otomatis:** `flutter analyze --no-pub` lulus tanpa temuan; `flutter test --no-pub` lulus (42 test), mencakup validasi/ukuran foto, simpan-persisten, ganti, hapus, gradient Profil, dan dialog Edit.
- **APK:** `flutter build apk --debug` berhasil; file `build/app/outputs/flutter-apk/app-debug.apk`. APK debug terbaru dipasang pada `emulator-5554`.
- **QA visual emulator:** Beranda terbuka, tetapi Profil mengarahkan ke dialog login karena emulator tidak memiliki sesi akun. Uji visual Profil dan alur pemilih galeri pada emulator belum dapat dilakukan tanpa kredensial. Test widget/service otomatis lulus; status ini belum dicatat sebagai verifikasi end-to-end emulator.
- **Status:** kode fitur dan pemeriksaan otomatis tersedia. Verifikasi nyata pilih/simpan/buka ulang/ganti/hapus melalui UI emulator masih tertunda sampai emulator memakai sesi akun yang dapat dibuka.

## Tahap 17 — Audit Figma, BRD, dan gap APK (audit selesai)

**Tanggal:** 16 November 2026

- **Cakupan audit:** semua 22 frame di halaman `Mockup Mobile` Figma (node `1:3`) dibaca melalui screenshot dan metadata: Beranda (`1:1380`), Berita (`1:1405`), Cuaca (`47:410`), Laporan (`1:1515`), Daftar Kontak (`1:1616`), daftar rute (`1:1651`), detail shelter (`277:186`), tiba (`293:813`), navigasi (`286:674`), Profil (`1:1699`), Daftar (`449:639`), Login (`456:806`), daftar donasi (`111:201`), detail donasi (`1:1782`), nominal (`1:1807`), pembayaran (`1:1856`), Keluarga Siaga (`383:378`), dua kondisi Status Aman (`390:491`, `390:545`), dua kondisi Status Tersimpan (`403:760`, `404:823`), dan Laporan Tersimpan (`404:869`). Tidak ada frame dalam daftar ini yang gagal dibaca. Frame `383:378` bernama “Layanan Darurat” pada inventaris tetapi isi visualnya adalah Keluarga Siaga; frame kontak instansi yang bisa dibaca adalah `1:1616`.
- **Tabel gap (Layar | Mockup | Kondisi sekarang | Aksi):**

| Layar | Mockup | Kondisi sekarang | Aksi |
|---|---|---|---|
| Navigasi utama | 5 ikon Beranda, Rute Evakuasi, Laporkan Bencana, Donasi, Layanan Darurat; item aktif berlatar hijau gelap dan lima label | 5 tab Beranda, Peta, Laporan, Berita, Lainnya; label belum terlihat; menu lain memuat fitur tambahan. Akses Profil melalui avatar/More. | Tahap 18: ubah tab sesuai BRD B-13 dan pindahkan Berita, Profil, Riwayat, Cuaca ke akses yang sesuai tanpa menghapus fungsi. |
| Beranda | Berita terbaru, peringatan, AI Flood Detection, Keluarga Siaga, cuaca; mockup memperlihatkan suhu 25°C | Data home dan berita diambil dari API; kartu peringatan mempertahankan status `unknown`, AI Detection tetap ada. API home memasok weather dan forecast yang sama. | Tahap 19: susun ulang komponen mengikuti frame; jaga status unknown dan sumber suhu bersama (BRD B-02). |
| Berita | Hero, daftar thumbnail dan pagination `1 2 3 … 10` | API `GET /news` mengembalikan daftar (maksimal 50 pada controller); UI memuat semua item tanpa pagination dan belum punya panel hero seperti mockup. | Tahap 19: hero, pagination klien berdasarkan jumlah data aktual; tetap gunakan detail berita dan label simulasi. |
| Cuaca | Pencarian, 3 metrik, tile prakiraan per jam/hari dengan ikon sesuai data | Detail cuaca memakai API forecast dan menyebut sumber/waktu; forecast berupa daftar berikon cloud statis. Tidak ada field kelembapan tanah atau pencarian lokasi pada UI. | Tahap 19: mapping ikon kondisi, tampilkan data yang tersedia saja dan pesan jelas untuk fitur/data yang belum tersedia (BRD B-03). |
| Rute Evakuasi / daftar shelter | Pencarian, peta, CTA rute teraman, daftar jarak dan ETA | `GET /shelters` tersedia; layar peta interaktif, pencarian, lokasi, dan fixture simulasi debug tersedia. Tidak ada API routing/ETA; jarak dihitung dari GPS untuk data koordinat. | Tahap 20: pertahankan peta dan fixture yang sudah aman; jangan menampilkan ETA tanpa service routing; tampilkan batasan keselamatan. |
| Informasi shelter | Foto (bila ada), nama/alamat, jarak, ETA, status verifikasi, fasilitas, CTA rute | API mengirim record shelter termasuk koordinat, tetapi belum ada layar detail yang mengikuti komposisi mockup/fasilitas terstruktur. Status verifikasi tersedia pada data backend dan harus dibedakan dari simulasi. | Tahap 20: detail berbasis record; hanya tampilkan foto/fasilitas/label resmi bila data mendukung; konsisten jarak (BRD B-01). |
| Navigasi dan Anda Telah Tiba | Instruksi belokan dan polyline; layar tiba dengan status aman | Tidak ditemukan endpoint atau service routing; layar navigasi turn-by-turn dan kedatangan belum ada. URL arah eksternal untuk koordinat tersedia pada alur shelter. API family check-in ada dan memerlukan autentikasi. | Tahap 20: interface routing + fallback peta eksternal jujur; layar tiba tanpa ETA/kondisi rekaan, kirim check-in memakai API family yang ada. |
| Laporkan Bencana | Form berurutan, lokasi di peta, waktu, korban, tingkat kosong, bukti dan Tips | Form multipart dan autentikasi sudah ada; lokasi, waktu, tingkat, bukti ditangani, dengan gerbang login. Perlu verifikasi urutan visual dan halaman sukses pada tahap implementasi; success saat ini dapat menampilkan rekomendasi shelter. | Tahap 21: susun komponen sesuai mockup dan pastikan halaman laporan menunjukkan lokasi kejadian, bukan shelter (BRD B-12). |
| Login / Daftar | Layar penuh dengan kartu, input, CTA login/daftar; lupa sandi tidak aktif | Login/register memakai API mobile dan flow modal/sheet; tidak ada API lupa kata sandi. | Tahap 21: selaraskan UI tanpa mengubah kontrak auth; tandai pemulihan sandi belum tersedia. |
| Kontak / Layanan Darurat | 5 kontak instansi + orang terdekat, aksi edit; frame keluarga darurat berisi kartu kontak | Hanya PCC 112 Kota Padang yang dicantumkan; menekan kontak membuka dialer. Belum ada pengelolaan/simpan kontak lokal atau endpoint kontak darurat. API family groups bukan API kontak telepon. | Tahap 22: kontak dapat dikelola dan disimpan lokal dengan status perangkat; instansi tanpa nomor terverifikasi tetap kosong. |
| Keluarga Siaga / Status Aman | Daftar anggota, checklist dan pilihan status Aman/Perlu Bantuan; status tersimpan | API family groups, members, invitations, check-in, reminder sudah ada. UI menggunakan check-in “Saya Aman”; perlu pastikan status awal netral dan beda warna No Info/Perlu Bantuan. | Tahap 20/22: gunakan API yang tersedia, tanpa status default atau sukses sebelum server mengonfirmasi (BRD B-10/B-11). |
| Status tersimpan / Laporan tersimpan | Halaman konfirmasi dengan lokasi relevan | Figma memperlihatkan shelter/lokasi terakhir pada kedua keadaan; data laporan mobile bersumber dari API reports dan receipt dapat memuat rekomendasi shelter. | Tahap 21: patuhi lokasi kejadian pada laporan; status lokasi keluarga hanya bila data consent/terakhir tersedia (BRD B-12). |
| Profil | Avatar, menu Aktivitas/Pengaturan dan keluar | API akun `GET /user` hanya memuat nama, email, telepon, alamat; foto profil lokal sudah tersimpan persisten di Application Support dari Tahap 16. Tidak ada endpoint upload foto. | Pertahankan foto lokal, aktivitas dan menu yang ada; jangan klaim sinkronisasi server. |
| Donasi | Listing/detail/nominal/metode dengan persentase dan identitas terverifikasi | Backend read-only menyediakan `GET /donation-campaigns` untuk program aktif terverifikasi; API menyatakan pembayaran dalam aplikasi tidak tersedia. Mobile saat ini hanya empty state informasional. Figma menampilkan persentase tidak cocok, nama/angka lintas-program tak konsisten dan narasi Flores pada program Padang. | Tahap 23: hubungkan listing ke API, tampilkan empty state bila kosong, hitung progress dan format Rupiah; jangan membuat transaksi/metode yang belum didukung (BRD B-04/B-05/B-06/B-09, TBD-07). |
| Riwayat dan pengaturan | Menu Profil dan halaman aktivitas | Riwayat laporan dan penilaian risiko tersedia di aplikasi; riwayat donasi/bantuan dan beberapa pengaturan belum didukung atau tidak memiliki API. | Tahap 18: pertahankan akses fitur yang ada; tandai fitur belum dirancang sebagai nonaktif/Segera hadir. |

- **Pemeriksaan backend read-only:** `routes/api.php` menyediakan `/home`, `/weather-forecast`, `/news`, `/donation-campaigns`, `/shelters`, `/weather-warning`, autentikasi, laporan, penilaian risiko, serta family groups/check-ins. Tidak ditemukan endpoint upload foto profil, routing, atau kontak darurat. Donation campaigns hanya baca dan responsnya menyatakan pembayaran tidak tersedia. Backend tidak diubah.
- **Deviasi mockup yang diwajibkan BRD:** jarak/ETA shelter harus konsisten dan ETA hanya bila layanan routing ada (B-01); suhu satu sumber (B-02); ikon forecast sesuai kondisi (B-03); persentase dan target donasi dihitung/utuh (B-04); data penggalang dan jumlah per program konsisten (B-05); narasi bencana sesuai program (B-06); No Info berbeda dari Perlu Bantuan (B-10); status tidak dipilih otomatis (B-11); lokasi laporan adalah lokasi kejadian (B-12); label/indikator aktif bottom nav (B-13). Mockup donasi, shelter dan status laporan yang tidak konsisten tidak akan ditiru.
- **File diubah:** hanya `STATUS_IMPLEMENTASI.md` untuk hasil audit. Belum ada perubahan kode pada Tahap 17.
- **Validasi Tahap 17:** `flutter analyze --no-pub` lulus tanpa temuan; `flutter test --no-pub` lulus (42 test); `git diff --check` bersih. Pemeriksaan diff untuk dokumen baru menggunakan intent-to-add agar Git memeriksa isi file.
- **APK dan QA visual emulator:** build dan pemasangan APK tidak dijalankan pada tahap audit-only; pemeriksaan emulator seluruh layar dijadwalkan untuk Tahap 24. QA emulator profil dari Tahap 16 masih tertunda karena emulator tidak memiliki sesi akun.
- **Status:** audit selesai; 22/22 frame terbaca. Belum ada perubahan kode pada tahap ini.
