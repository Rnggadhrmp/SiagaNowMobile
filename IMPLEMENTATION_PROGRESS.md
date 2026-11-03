# SiagaNow Mobile Implementation Progress

Updated: 1 November 2026

## Stage 1 — Audit

Completed before application edits. See [FUNCTIONAL_AUDIT.md](FUNCTIONAL_AUDIT.md). Flutter source and tests were inspected in this workspace. Laravel is at `C:\College\SiagaNow`; routes, controllers, models, migrations, and tests were inspected. The reference implementation status was treated as background and current code was checked independently.

## Stages 2–7 — Mobile and backend integration

| Area | Result | API / tables |
|---|---|---|
| Central API client | `SIAGANOW_API_URL` is centralized; defaults are Android emulator `10.0.2.2` and Web `127.0.0.1`. JSON and multipart calls have 15-second request timeout, structured HTTP/validation errors, invalid JSON/shape handling, and network/timeout messages. | Laravel `/api`; no direct MySQL access |
| Authentication | Login and registration use existing contracts. Registration sends name, phone, email, password and confirmation. Token is saved securely; profile is fetched before setting signed-in state. Restore checks `/user`; 401/403 clears invalid token. Logout calls server and clears local token, with a message if remote revocation could not be confirmed. | `POST /login`, `POST /register`, `GET /user`, `POST /logout`; `users`, `personal_access_tokens` |
| Home / weather / news | Home displays current BMKG weather and available forecast intervals with source/update details, plus backend warning and statistics states. News uses its endpoint and labels simulations. Warning remains explicitly `unknown` per current `/home`; the point-specific warning endpoint requires coordinates and is not called without a selected point. | `GET /home`, `GET /news`; `weather_warnings`, `disaster_events` where applicable; authoritative live news/statistics are not available |
| Shelter search | Search calls Laravel `q` capability. Records show source and verification state; simulation locations are labeled. Map/route panel says interactive mapping and safe routing are unavailable. | `GET /shelters?q=...`; `shelters` |
| Reports | No sample coordinates are prefilled. Users can request device GPS or edit coordinates, and choose event date/time. Duplicate taps are blocked. Up to five supported photo/video attachments can be selected and uploaded via Laravel multipart. Actual report ID/status is shown. History is authenticated and ownership-filtered. Backend now preserves omitted casualty counts as NULL and explicit zero as 0. | `POST /reports` multipart, `GET /reports`; `disaster_reports`, `users`, `personal_access_tokens` |
| Navigation / account | Home quick actions work; News is a tab; More opens profile/history. PCC 112 is scoped to Padang and opens dialer. Donation/payment and Keluarga Siaga remain clearly unavailable. | As listed above; `GET /user` |

## Files changed

- Flutter: `lib/main.dart`, `pubspec.yaml`, `pubspec.lock`, Android manifest and iOS location usage description.
- Flutter tests: `test/api_models_test.dart`.
- Audit and progress records: `FUNCTIONAL_AUDIT.md`, `IMPLEMENTATION_PROGRESS.md`.
- Laravel: `C:\College\SiagaNow\app\Http\Controllers\DisasterReportController.php`, `C:\College\SiagaNow\database\migrations\2026_10_30_000001_allow_unknown_casualty_counts_on_disaster_reports_table.php`, and `C:\College\SiagaNow\tests\Feature\MobileApiTest.php`.

## Verification

- Flutter analyze: passed, no issues.
- Flutter tests: passed, 5 tests (four model parsing tests and the existing loading widget test).
- Flutter Web release build with `SIAGANOW_API_URL=http://127.0.0.1:8000/api`: passed.
- Laravel suite: passed, 23 tests / 138 assertions, using PHPUnit's in-memory SQLite. Includes auth validation/token protection, shelter search, report ownership, unknown-versus-zero casualty persistence, private-disk attachment storage, and invalid MIME rejection. The BMKG-dependent API test fakes its upstream service.
- Android debug APK: built successfully. The failure was caused by JDK `Selector.open()` failing under the inherited Windows temp path (`Unable to establish loopback connection`, `SocketException: Invalid argument: connect`). Setting `TEMP` and `TMP` to a short workspace path fixed that issue. An IDE Gradle import then held the normal project build lock, so the successful `assembleDebug` used a separate project cache without stopping or changing the IDE process. APK: `C:\College\SiagaNowMobile\build\app\outputs\apk\debug\app-debug.apk` (161,998,457 bytes). Installed and launched on Android emulator `emulator-5554` (`sdk_gphone64_x86_64`, API 37).
- Public API smoke check: `/api/home`, `/api/weather-forecast`, `/api/weather-warning?lat=-0.95&lng=100.42`, `/api/news`, and `/api/shelters?q=Kuranji` returned 200; guest `/api/reports` returned 401. Forecast reported `data_type=actual`, `source=BMKG`, and available data. The warning lookup reported BMKG `no_warning_found`, with the API caveat that this does not guarantee safety. News and shelter endpoints reported simulation data. Home's warning remains unknown until a point is checked.
- Flutter Android emulator UI smoke: app loaded `/api/home` and displayed a 27° BMKG forecast with source, location and update time; warning remained unknown and statistics were labeled training data. `/api/shelters` displayed simulation entries; search `Kuranji` returned one visible match, `Contoh Shelter Kuranji`, labeled simulation / not verified. Laravel ran against a disposable SQLite database under the mobile workspace for this emulator check, not MySQL; the temporary server was stopped afterward.
- Laravel's effective target was environment `local`, MySQL driver, database `siaganow`. The new migration was the only pending migration and was applied successfully. `injured` and `deceased` are nullable; the existing `disaster_reports` table has 1 row after migration. No records were reset or deleted. Laragon MySQL remains running; the temporary Laravel HTTP server was stopped after smoke checks.
- `git diff --check`: no whitespace errors; only expected LF/CRLF normalization warnings remain.

## Phase 2 — real MySQL and emulator verification — 1 November 2026

- Read `.env` fields without displaying credential values. Effective local target: `APP_ENV=local`, MySQL `siaganow` at `127.0.0.1:3306`. MySQL 8.4.3 had been stopped, so the existing Laragon server was started with its existing configuration/data directory. `php artisan migrate:status` verified all 12 migrations `Ran`; no migrations or data-changing SQL were run.
- The APK used the Android emulator default API base `http://10.0.2.2:8000/api`; the base remains configurable with `--dart-define=SIAGANOW_API_URL=...`. Laravel is bound to `0.0.0.0:8000` using the local `.env` configuration. The emulator API host mapping reached it, as confirmed by the Laravel request log.
- Real-server API results: `/api/home` returned 200, weather `data_type=actual` with source BMKG and Padang location; statistics remained simulation and warning remained unknown. `/api/shelters?q=Kuranji` returned 200 with one simulation fallback result. Guest `/api/reports` returned 401.
- Flutter emulator UI results: Home rendered the BMKG forecast; shelter search for `Kuranji` rendered `Contoh Shelter Kuranji`, labeled simulation / not verified. The MySQL shelter count was 0, which explains the API fallback. Final `disaster_reports` count was 1; no report POST or other data-changing request was issued, so existing records were preserved.
- The backend contract and Flutter payloads align for login (`identifier`, `password`) and registration (`name`, `phone`, `email`, `password`, `password_confirmation`). This was code inspection only; no credentials were supplied or documented, and no account was created. Login, token persistence, profile, logout, registration, report submission, history ownership, and attachment upload remain unverified through Flutter. Backend feature tests previously covered report persistence, ownership, and private-disk attachment validation; they do not substitute for the blocked Flutter-authenticated flow.
- No Laravel backend source was modified during Phase 2. The emulator, local MySQL process, and local Laravel server remain running to support the next authorized test.

## Remaining limitations

- Nullable casualty columns were verified on live MySQL. A live authenticated report submit and subsequent row read still require an authorized test account; none was supplied.
- Interactive map tiles/picking, verified shelter/hazard layers, safe evacuation routing, and location-specific warning lookup remain unavailable. GPS and manual coordinates are supported for reports.
- No authorized test account or credentials were found in project artifacts. Authenticated login, token persistence, profile, logout, report submission, history ownership, and Flutter attachment upload were not performed. The emulator was available for public Home and shelter UI flows; no physical-device test was run.
- Verified shelters/live incident data, donation payments, Keluarga Siaga, and official hazard zones remain unavailable from current backend/data sources.

## Phase 3 — frontend completion and Figma alignment — 1 November 2026

### Implemented in this pass

- Home now follows the mobile mockup's mint/green palette and card order: latest news, warning status, preparedness shortcut, weather, and forecast. It reads `/api/home` and `/api/news`, displays actual BMKG weather and interval forecasts, labels demonstration news as simulation, labels disaster statistics as training data, and renders the warning status as unknown when the API has not checked it.
- The weather card opens a dedicated detail screen with the returned BMKG location/source, interval forecast rows, and warning status. The Padang PCC 112 service opens an emergency contacts page; personal/family contacts remain explicitly unavailable.
- The top profile control opens the account flow. A root-context defect found on emulator was fixed by using the `MaterialApp` navigator and scaffold-messenger keys. The guest login sheet and register mode now open; login and registration retain the existing Laravel contracts. Password visibility toggles are available.
- News cards open an in-app detail view from the returned API item. Shelter search remains connected to `GET /api/shelters?q=...`; its results preserve the API's simulation/verification labels. Report form validation now runs before the guest login gate; no sample coordinates are prefilled. Report history remains authenticated and uses the owner-filtered API.
- Existing routes and API were not changed. No new dependency was introduced. The app theme and navigation were adjusted while retaining existing report, shelter, profile, and service code.

### Screen-by-screen state

| Screen / flow | Current status |
|---|---|
| Home | Figma-aligned layout and palette; live API weather/forecast shown. Unknown warning, training statistics, and simulation news are labeled honestly. Refresh remains available. |
| Weather detail | Opens from the Home weather card and uses the current `/api/home` response for weather, forecasts, and warning state. |
| News list and detail | API-backed list; simulation banner; each list item opens its returned content in a detail page. News source currently returns demonstration records. |
| Maps / shelters | Search and empty/error states connect to the API. No interactive map, verified shelter marker, detail endpoint, or safe-route API exists; simulated results are not described as safe locations. |
| Report | Existing form supports event/date/time/coordinates/casualties/description and up to five photo/video files per backend constraints. Guest field validation was exercised. Authenticated submit, receipt, and history could not be run without an authorized test account. |
| Login / register | Both forms open and validate. Password visibility works. No credentials were supplied; no login, registration, token persistence, profile retrieval, or logout request was attempted. |
| Profile / report history | Protected API wiring and owner-filtered history retained. Profile entry is reachable from the app header and More screen. Authenticated profile and logout remain unverified without a permitted account. |
| More / emergency / unsupported services | Padang PCC 112 dialer remains accessible. Donations, Family Siaga, and mobile risk assessment are explicitly unavailable; the web-only risk controller has no mobile API endpoint. |
| Emergency contacts | Details page reachable from More; Padang PCC 112 opens the dialer. No personal contact list is represented as real or stored. |

Figma inspection covered the mobile page's Beranda, Berita, Cuaca, Laporkan Bencana, Profil, Login, evacuation route, and emergency-contact frames. Home, News, and evacuation-route screenshots were retrieved; design-context calls for Home, Weather, Report, and Profile succeeded. Some later per-node screenshot requests timed out. The page's original photographic/illustration assets and typography are not fully reproduced; the principal visual alignment in this pass is the Home hierarchy, palette, cards, and app navigation. The sample satellite route, shelter markers, and active-warning illustration in Figma were not presented as real data.

### Exact verification results

| Check | Result | Scope |
|---|---|---|
| Flutter dependencies | `flutter pub get` completed as part of analyze/test/build. Existing lockfile remained resolved; 23 newer versions were reported as incompatible with current constraints. | No dependency version upgrades were made in this pass. |
| Flutter analysis | `flutter analyze`: **No issues found**. | Current Flutter workspace. |
| Flutter tests | `flutter test`: **5 passed, 0 failed** (4 model tests and 1 loading widget test). | These automated tests do not claim backend-authenticated end-to-end coverage. |
| Android APK | `flutter build apk --debug`: **succeeded**. APK at `build/app/outputs/flutter-apk/app-debug.apk`; installed on `emulator-5554` and launched. Build used workspace `.tmp` for `TEMP` and `TMP` due the inherited Windows temp-path/loopback problem recorded above. | Android emulator `sdk_gphone64_x86_64`; no physical-device test. |
| Emulator Home/API | The app displayed 27°C, Hujan Ringan, BMKG source and Belakang Pondok/Padang Selatan location from the running Laravel API. The forecast response contained actual BMKG interval data. The warning stayed unknown; the statistics were explicitly training data. | Public GET only; emulator API base `http://10.0.2.2:8000/api`. |
| Emulator News | The list loaded demonstration news and displayed the simulation banner. Tapping an item opened its detail screen. | Public GET `/api/news`; this is not an official live-news feed. |
| Emulator shelter search | Searching `Kuranji` returned `Contoh Shelter Kuranji`, marked simulation / not verified. The map and safe routing remained unavailable. | Public GET `/api/shelters?q=Kuranji`; current shelter table has no real rows. |
| Emulator guest forms | Login sheet opened without a runtime exception after the navigator-context fix. Empty login showed required-field validation; Register showed name, email, and password-confirmation fields. Empty guest report submission displayed title/coordinate/description validation. | No credentials were entered and no login, registration, report POST, or attachment upload was issued. |
| Weather and contacts navigation | Home weather card opened the weather detail page; the More tab's PCC 112 card opened the emergency contacts page. | The dial action itself was not triggered. |
| MySQL preservation | Read-only counts after the emulator checks: `disaster_reports = 1`, `shelters = 0`. | No write endpoint, migration, or database mutation was performed in this pass. |
| Laravel tests | Not rerun; prior verified result remains 23 tests / 138 assertions. | Backend source was not changed in this pass. |

The Figma page has more visual detail than the implemented Flutter screens. News uses app-native cards rather than all original imagery; profile, registration, contacts, and routing are functional/explicit states but are not complete pixel matches. These remain visual polish work; unsupported server-backed features remain blocked by the API/data limitations above.

## Phase 4 — Figma assets and final Android verification — 1 November 2026

- Inspected the Mobile Figma page metadata for all 22 top-level frames and compared available Figma references with current Flutter screen captures. Full pixel parity for every frame remains incomplete and is documented in `FUNCTIONAL_AUDIT.md`.
- Added the original Figma header waves, landscape footer, flood-warning illustration, weather illustration, login/register illustration, and simulation-only news photography under `assets/images/` and `assets/illustrations/`. Added Poppins Regular/Medium/Bold with its SIL OFL 1.1 text under `assets/licenses/`; Poppins is now the app theme font.
- Improved Home, News, report form, profile, and shared app-bar styling while preserving the Laravel integration and existing navigation. No backend or database files were changed. The Figma sample map pins were excluded to avoid presenting unverified shelters as real.
- `flutter pub get` succeeded; 23 newer package versions remain outside current constraints. Final `flutter analyze --no-pub` reported no issues. Final `flutter test --no-pub` passed all 5 tests.
- Final `flutter build apk --debug` succeeded. APK: `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk` (185,643,302 bytes). The installed APK launched on `emulator-5554` (Android API 37). Emulator navigation/screens visually checked: Home, News, report, profile, and shelter/map. No filtered Flutter or Android runtime errors appeared in logcat during those checks.
- An emulator session existed before this Phase 4 work and was restored after APK replacement; its authenticated Profile screen loaded via `GET /api/user`. I did not treat that existing account as a test account, and performed no login submission, logout, report POST, attachment upload, registration, or database write. Report ownership and authenticated writes remain unverified through Flutter.
- No current database counts were queried during Phase 4. Existing database records were preserved by issuing no write or migration request. The Laravel 23 tests / 138 assertions remain the last verified backend result; backend tests were not rerun because backend source was unchanged.

## Phase 5 — missing features and integration — 1 November 2026

- Family Siaga MVP, backed by the additive `family_groups` / `family_members` schema and authenticated owner-scoped CRUD APIs. No invitation, location sharing, or emergency delivery is implemented.
- Risk assessment request/history UI uses the existing risk model/table and supported inputs; requests remain pending with limitations, with no fabricated score.
- Donation screen explains that there is no verified configured program or in-app payment. Shelter details expose provenance and simulation status.
- Fixed `AppBarTheme.flexibleSpace` analyzer error and added a shelter detail sheet. Full details and exact run results are recorded in `FUNCTIONAL_AUDIT.md`.
- Verified: `flutter pub get`; `flutter analyze --no-pub` clean; `flutter test --no-pub` 5/5; Android debug APK succeeded and installed/launched on `emulator-5554`; public API smoke Home/News/Shelters 200 and guest Reports 401; Laravel **28 tests / 172 assertions** pass; 21 API routes; additive migration Ran.
- MySQL counts after additive migration: family groups 0, family members 0, disaster reports 1, shelters 0. No Flutter authenticated writes were attempted because the only emulator session was not established as an authorized test account.

## Phase 6 — core stabilization — 1 November 2026

- Current emulator navigation into Family Siaga loaded the API-backed empty state with no `_dependents.isEmpty` assertion. No full exception stack was produced, so the supplied crash root cause remains unverified; no root-cause fix is claimed. Async Family loads/mutations/login continuation now check `mounted` before state updates, with a widget test for empty-state and back navigation.
- Home's Family shortcut now opens the Family screen instead of showing an obsolete unavailable dialog.
- Risk controls now expand to available width, use concise rainfall labels, and wrap the location button text. Mocked widget layout tests passed at 320×640 and 375×812 logical pixels. API client accepts injectable client/token reader for isolated request tests.
- Figma metadata for 22 top-level frames was inspected. The context request timed out; node `383:378` is an emergency services frame, and no dedicated risk/family top-level frames were returned. Full Figma parity remains outstanding.
- Final checks: `flutter pub get` succeeded; analyzer clean; **7 Flutter tests passed**; debug APK built (185,683,103 bytes) and installed/launched on API 37 emulator. Home, Weather detail, More, Donation, and Family empty state were visually checked; no assertion/fatal log on Family navigation.
- No Laravel source or database changes in this phase; previous backend verification remains 28 tests / 172 assertions. No authenticated write was made.

## Phase 7 — local API and Flutter regression — 2 November 2026

- Read-only repository check before edits: mobile `main` at `c962ef9`, clean; backend `feature/perbaikan-api`, two commits ahead of origin, clean. No pull/merge was performed.
- Started Laravel using `php artisan serve --host=0.0.0.0 --port=8000`. Local API and host LAN address `192.168.1.9:8000` both answered. Public `/api/home`, `/api/weather-forecast`, `/api/news`, and `/api/shelters?q=Kuranji` returned 200 with `data_type=simulation` in this session. Guest requests to `/api/reports`, `/api/user`, and `/api/family-groups` returned 401 as expected; no write endpoints were called.
- `flutter pub get` restored packages from the existing pubspec/lockfile; it did not upgrade constraints. Initial analyzer output exposed invalid `double.fromEnvironment` calls for default map coordinates. Replaced them with string compile-time environment values parsed defensively while retaining the same Padang defaults and visual behavior.
- Updated Family widget-test HTTP fixtures to return the empty `GET /family-memberships` response now required by `FamilyPage`. This fixed five stale-fixture failures without changing Family application behavior.
- Regression: 12 Flutter tests passed. Analyzer reported no errors and two informational lints (deprecated `DropdownButtonFormField.value`, and braces around one `if`); these are not runtime errors. Standard Flutter APK build failed closing Kotlin incremental caches because the Pub cache is on `C:` while the mobile workspace is on `D:`. Direct Gradle `assembleDebug` with Kotlin incremental compilation disabled succeeded. APK built with API base `http://192.168.1.9:8000/api` (185,650,376 bytes).
- Physical RMX2001 is currently reported by ADB as `unauthorized`; its RSA debugging authorization has not been accepted in this session. Therefore the just-built APK has not been installed/launched on the physical phone, and no physical-device API, login, profile, GPS, upload, reports/history, or Family flow is claimed as tested here. No credentials were available; no registration/login or authenticated writes were attempted.
- No Laravel source, migration, or database data was changed. UI palette, typography, icons, navigation, and layout were not redesigned in this phase.

### Next physical-device checkpoint

Unlock the RMX2001 and accept its Android USB debugging authorization prompt (select “Always allow from this computer” only if appropriate). Then confirm ADB reports the device as `device`; after that install the generated APK, open it, and verify public Home/News/Shelter/API states before any authorized-account flows.
## Phase 8 — RMX2001 physical QA follow-up — 2 November 2026

- This section supersedes Phase 7's initial `unauthorized` device status. User approved USB debugging; ADB now identified `4PJNUSZ5G6TSZD6T` as RMX2001. Current APK installed and opened.
- The PC Wi-Fi profile is `Public`. Despite the device and PC being on `192.168.1.0/24`, direct HTTP from the phone to the PC timed out. No firewall/profile setting was changed. A temporary USB tunnel `adb reverse tcp:8000 tcp:8000` allowed the app to reach Laravel; the APK was built with QA base `http://127.0.0.1:8000/api`. GET requests from the app to `/api/home`, `/api/news`, and `/api/shelters` appeared in the Laravel server log.
- On-device screens reviewed: Home, News, Maps/Shelter, Report form, More, Weather detail, and guest Family/login gate. Home weather used the clearly labeled local simulation fallback; warning stayed unknown; statistics/news/shelters remained labeled demonstration/training. OSM basemap rendered, but shelter points are simulation and no route is represented as safe.
- Report GPS control successfully populated current device coordinates after granting location while in use. The coordinates were not submitted and the screenshot containing them was deleted. Android file picker opened from the attachment button; no item was chosen and no upload occurred. Report submit/history and profile/Family management remain behind authenticated account access.
- Guest API checks for reports/user/family groups returned 401. No valid test credentials were available. Login, token persistence, profile, report POST, attachment upload, report history, and authenticated Family CRUD/check-in/reminders/invitations remain unverified end-to-end.
- Laravel suite initially failed 2 of 30 tests due cached auth guards in test setup while switching bearer tokens. Added `Auth::forgetGuards()` before changing test identities; full suite then passed **30 tests / 209 assertions** on in-memory SQLite. Flutter `flutter test --no-pub` passed **12 tests**. Final `flutter analyze --no-pub` completed with no issues after replacing the deprecated dropdown initializer. The standard Flutter APK command hit cross-drive Kotlin incremental cache closure errors; direct Gradle build with incremental compilation disabled succeeded and APK was installed.
- Database MySQL was not modified; no migration or write endpoint was run. Design/theme/layout were kept intact.

### Remaining device checkpoint

- For direct Wi-Fi API testing, Windows currently classifies the Wi-Fi network as Public. A narrow inbound firewall exception or changing the trusted network profile would be required; neither was changed. USB reverse can continue to be used for QA.
- Account-backed device flows require an authorized test account. No test account was created or inferred from existing phone/device data.

- Final post-lint rebuild: analyzer clean, 12/12 Flutter tests pass; APK **185,653,984 bytes** rebuilt and installed/launched on RMX2001 at 17:01 local. Home API GETs were logged by Laravel through the active USB reverse tunnel.

## Phase 9 — QA akun lokal: autentikasi API — 2 November 2026

- Dengan persetujuan pengguna, dibuat satu akun dummy QA pada MySQL lokal backend yang sudah diverifikasi (127.0.0.1:3306, database siaganow). Kredensial hanya disampaikan melalui percakapan, tidak disimpan di repo; akun tidak dihapus.
- API Laravel diuji langsung: login berhasil, GET /api/user mengembalikan profil akun QA, logout mencabut token, dan token yang dicabut ditolak 401. Tidak ada migration atau perubahan skema.
- Login Flutter pada RMX2001, pemulihan sesi, tampilan profil, dan logout belum diuji di perangkat karena ADB melaporkan perangkat unauthorized pada host ini. Setelah USB debugging diizinkan kembali, lanjutkan USB reverse ke Laravel port 8000 dan uji alur pada APK yang terpasang. Password tidak dicatat di dokumentasi.

## Phase 10 — autentikasi end-to-end RMX2001 — 2 November 2026

- Setelah pengguna mengizinkan USB debugging, perangkat kembali tersambung. USB reverse port 8000 menghubungkan APK yang telah terpasang ke Laravel lokal.
- Login dengan akun QA berhasil. Laravel mencatat POST /api/login dan GET /api/user. Halaman Profil pada perangkat menampilkan nama, email, dan nomor HP akun.
- Aplikasi di-force-stop dan dibuka kembali tanpa menghapus data aplikasi; sesi dipulihkan, home menunjukkan status masuk, dan Laravel mencatat GET /api/user saat restore.
- Logout berhasil dan aplikasi kembali ke tampilan tamu. Baris token Sanctum akun QA berubah dari satu menjadi nol. Setelah aplikasi dibuka ulang, status tetap tamu. GET /api/user tanpa token menghasilkan 401; uji API dengan token revoked juga menghasilkan 401.
- Tidak ada perubahan source Flutter, backend, skema, atau migration untuk QA ini. Profil hanya didukung baca; GET /api/user tersedia, sedangkan endpoint update tidak ada dan tombol edit menyatakan fitur tersebut belum tersedia. Kredensial tidak dicatat di file progres; akun QA tetap dipertahankan.
- Berikutnya: audit alur formulir laporan dan riwayat. Jangan membuat laporan bencana fiktif sebagai bagian dari uji end-to-end; submit perlu kejadian nyata yang disediakan pengguna atau persetujuan terpisah untuk record QA yang jelas ditandai.

## Phase 11 — form laporan: validasi dan pemeriksaan RMX2001 — 2 November 2026

- Pada APK di RMX2001, form guest diperiksa: koordinat tidak diprefill; validasi kosong menandai judul, kedua koordinat, dan deskripsi; form tetap guest dan tidak membuat permintaan submit. Jumlah disaster_reports untuk akun QA tetap nol.
- Screenshot menunjukkan pesan batas koordinat terpotong satu baris. Input form kini mengatur errorMaxLines menjadi 2 agar teks penuh terlihat; identitas visual dan layout normal tidak diubah. APK debug terbaru dibangun memakai Gradle dengan Kotlin incremental off (Flutter CLI build masih terkena masalah cache lintas-drive), dipasang dengan install replace yang mempertahankan data, dan hasil pesan lengkap diverifikasi di HP.
- Tes: flutter analyze bersih, flutter test seluruh **13 tes lulus**, termasuk tes widget baru untuk pesan validasi dan mencegah login/pengiriman ketika guest. git diff --check bersih.
- API Laravel MobileApiTest sebelumnya lulus **8 tes / 40 assertion** di test SQLite, termasuk kepemilikan riwayat serta validasi lampiran. Tidak ada laporan fiktif dibuat pada database lokal. Pengiriman laporan/upload Flutter masih menunggu kejadian nyata yang disediakan pengguna atau persetujuan terpisah untuk record QA yang jelas ditandai.
- Berikutnya: uji riwayat laporan akun kosong (read-only), lalu lanjutkan shelter/peta atau fitur akun sesuai dukungan endpoint yang tersedia. Jangan menyimpan laporan simulasi sebagai kejadian nyata.

## Phase 12 — riwayat laporan autentikasi di perangkat — 2 November 2026

- Setelah perbaikan validasi, login ulang pada RMX2001 berhasil. Endpoint GET /api/reports dipanggil oleh aplikasi; riwayat akun QA kosong dan UI menampilkan empty state yang benar.
- Logout dilakukan lagi setelah pemeriksaan. MySQL lokal akhir: nol laporan milik akun QA dan nol personal access token QA. Akun QA dummy tetap dipertahankan sesuai persetujuan pengguna.
- Submit multipart dan lampiran tidak dikirim karena tidak ada kejadian nyata untuk dilaporkan; API backend tetap memiliki tes terisolasi untuk penyimpanan, validasi MIME, batas dan ownership. End-to-end unggah lewat HP masih belum terverifikasi.
- Tahap laporan yang dapat diuji tanpa merekayasa kejadian selesai: autentikasi, validasi lokal, riwayat kosong. Berikutnya audit fitur shelter/peta atau Family Siaga yang sudah punya API; data kejadian hanya diuji kirim dengan detail nyata atau persetujuan khusus.

## Phase 13 — kontrak multipart laporan (mocked) — 2 November 2026

- Ditambahkan tes ApiService.uploadReport dengan MockClient untuk memverifikasi Bearer Authorization, multipart/form-data boundary, field laporan yang diserialisasi, serta evidence[]/filename. Respons dibuat oleh mock; tidak ada request ke Laravel dan tidak ada record database.
- Flutter analyze tetap bersih; seluruh **14 tes Flutter** lulus.

## Phase 14 — Family Siaga read-only QA pada RMX2001 — 2 November 2026

- Login QA pada HP memuat GET /api/family-groups dan GET /api/family-memberships; layar menampilkan empty state grup dengan jelas. Tidak menekan Buat grup atau Gabung, dan tidak membuat anggota, undangan, check-in, atau pengingat.
- Logout sukses setelah pemeriksaan. Database akhir untuk akun QA tetap kosong: 0 family groups, 0 family members, 0 reports, 0 personal access tokens. Akun tidak dihapus.
- Laravel MobileFamilyRiskApiTest lulus **7 tes / 71 assertion** di database test. Uji CRUD keluarga di perangkat belum dilakukan karena akan menulis data keluarga contoh ke MySQL lokal; minta izin khusus jika perlu end-to-end mutasi.

## Phase 15 — konten demo cuaca/berita dan foto ilustrasi — 2 November 2026

- Tema, warna, Poppins, ikon, layout, dan navigasi dipertahankan. Flutter memetakan `image_key` API ke dua aset lokal; layar detail menampilkan caption lokasi asal serta kredit foto.
- Aset Unsplash yang telah diperiksa secara visual dan dioptimalkan melalui CDN ke JPEG 1000 px: Iqro Rinaldi, [foto banjir Rawa Jati/Jakarta (4 Maret 2025)](https://unsplash.com/photos/flooding-submerges-houses-people-gather-to-seek-shelter-L0MwD0NcZEk), 172,755 byte; Justin Hu, [pegunungan berhutan Tahiti setelah hujan](https://unsplash.com/photos/a-lush-green-mountain-covered-in-clouds-and-trees-Y0Vaj15OE5s), 155,737 byte. Keduanya berlisensi Unsplash. Foto banjir bukan kejadian Sumatera Barat; foto Tahiti hanya ilustrasi alam, bukan peta/rute/zona risiko.
- API `news` berisi tiga materi edukasi/skenario, semuanya tetap bertipe simulasi pada tingkat respons dan item. Tidak ada transaksi atau data kejadian nyata yang dibuat. Atribusi dan konteks disimpan di backend `config/siaganow.php`.
- Fallback BMKG tetap mempertahankan permintaan aktual. Bila gagal dan Mode Demo aktif, API menyajikan kondisi saat ini dan tiga interval cuaca simulasi; nilai kelembapan adalah kelembapan udara, humidity soil tidak diada-adakan. Status `simulation/fallback` dan pesan kegagalan BMKG tetap disertakan.
- Verifikasi backend: `php -l` dua file lulus; `BmkgForecastTest` dan `DemoNewsTest` lulus **5 tes / 33 assertion**. Endpoint lokal `/api/home` dan `/api/news` menjawab 200; home memiliki tiga interval prakiraan simulasi, berita bertipe simulasi.
- Verifikasi Flutter: `flutter test` **14 lulus**; analyzer menyisakan satu info lint lama pada `lib/main.dart:3197` (kurung kurawal pada if, di luar perubahan ini). APK debug berhasil dibangun dengan Gradle workaround Kotlin cache; kedua foto terverifikasi ada di asset bundle APK (masing-masing 172,755 dan 155,737 byte). Screenshot RMX2001 pada layar Berita memperlihatkan materi simulasi dan foto ilustrasi. Regresi Laravel lengkap: **32 tes / 221 assertion lulus**.
- Catatan insiden instalasi: `flutter install` gagal karena mencari `app-release.apk` yang tidak tersedia dan secara tidak terduga menghapus paket lama sebelum gagal. Pemeriksaan ADB memastikan paket lama sudah hilang; APK debug kemudian dipasang kembali dengan ADB, diluncurkan, dan USB reverse terverifikasi aktif. Akibatnya penyimpanan privat aplikasi lokal dari instalasi lama (termasuk preferensi lokal) hilang dan tidak dapat dipulihkan. Saat itu sesi akun QA telah logout; uji Phase 14 mencatat nol token/laporan/grup/anggota, dan tidak ada data backend yang dihapus/diubah pada tahap ini. Kejadian ini dicatat sebagai kesalahan operasional.
- Pemeriksaan visual RMX2001: setelah aplikasi diberi waktu memuat dan dibuka ulang, Beranda menampilkan foto berita dari API dengan label “BERITA · SIMULASI”, status peringatan “belum diketahui”, cuaca contoh 28°C, kelembapan udara, statistik bertanda latihan, serta materi prakiraan contoh. Screenshot Beranda tersimpan di workspace Codex untuk pemeriksaan tahap ini.
- Belum diuji secara visual: tab daftar Berita dan layar detail/kredit foto pada RMX2001. Akses runtime ke feed cuaca BMKG aktual masih gagal di lingkungan ini; fallback simulasi aktif dan label/statusnya jujur. Endpoint lokal `/api/home` serta `/api/news` merespons 200 dari host; kartu Beranda pada perangkat memuat konten API setelah request selesai.

## Phase 16 — logo website pada header mobile — 2 November 2026

- Menyalin aset website `public/images/siaganow-nature-emblem.png` apa adanya ke `assets/images/siaganow-nature-emblem.png` (384×256, 62,384 byte). Ikon shield placeholder di header diganti `Image.asset` berlabel aksesibel, ukuran 68×45 dan `BoxFit.contain`; warna, font, layout lain, dan navigasi tetap.
- Analyzer melaporkan satu info lint yang sudah ada terkait braces pada `lib/main.dart`; seluruh **14 tes Flutter lulus**. Build APK debug berhasil dengan workaround Gradle/Kotlin yang pernah digunakan sebelumnya. APK dipasang menggunakan `adb install -r` dan RMX2001 tetap membuka Beranda; screenshot logo diperiksa secara visual.
- Database Imam diperiksa melalui database review sementara terisolasi, dibandingkan dengan DB MySQL aktif, lalu database review dihapus. Tidak ada database utama yang diubah dan tidak ada data akun/token/laporan/keluarga/risk/warning yang dipindahkan; temuan lengkap dicatat pada `IMPLEMENTATION_STATUS.md` website.

## Phase 17 — splash screen dan onboarding Flutter — 3 November 2026

- Menambahkan alur splash singkat dan intro tiga halaman (Kenali Risiko di Sekitarmu, Informasi dan Peta Bencana, Keluarga Siaga) pada startup. Logo website yang telah tersedia di `assets/images/siaganow-nature-emblem.png` dan ilustrasi lokal yang sudah ada digunakan; peta hanya ilustratif tanpa pin/lokasi shelter atau zona risiko. Warna mint/green, krem, font Poppins, dan komponen Home maupun halaman lain tidak diubah.
- Tombol Lewati, Selanjutnya, pagination, dan Mulai Sekarang diimplementasikan. Status onboarding disimpan dengan `shared_preferences` key `siaganow.onboarding.completed.v1`. Alur pemulihan token dan profil tetap menggunakan Secure Storage/API yang telah ada. Sesi token yang sudah ada dipertahankan dan menandai intro selesai agar pengguna lama tidak terhenti di onboarding.
- File terkait: `lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml`, `pubspec.lock`. Dependensi SharedPreferences ditambahkan pada versi 2.5.6; tidak ada perubahan backend, API, database, maupun migration. File progres ini juga diperbarui.
- Verifikasi: seluruh **16 Flutter test lulus**, termasuk tes penyimpanan SharedPreferences, Skip, dan perpindahan tiga halaman hingga Mulai Sekarang. `flutter analyze` selesai dengan satu info lint yang sudah ada di `lib/main.dart` (curly braces, sekitar baris 3634), tanpa error analyzer. `git diff --check` bersih (hanya peringatan normal konversi akhir baris Git).
- Build Android debug berhasil melalui Gradle (`BUILD SUCCESSFUL`, APK 226,051,651 byte, 3 November 2026). Build menunjukkan peringatan deprecasi Kotlin/Gradle dan Android SDK XML yang tidak menghalangi build. APK dipasang menggunakan `adb install -r` pada RMX2001; data aplikasi tidak dihapus. USB reverse port 8000 diaktifkan.
- Pengujian perangkat: aplikasi terbuka pada RMX2001 dan force-stop/reopen kembali ke Home. Instalasi mempertahankan sesi login lama; karena jalur startup sengaja melewati onboarding untuk token yang sudah tersimpan, alur first-run/splash/intro belum terlihat dan tidak diverifikasi secara visual pada perangkat. Status completion preference tercatat `true` sesudah startup. Screenshot Home hasil reopen: `C:\Users\lenovo\.codex\visualizations\2026\10\25\01a1723c-cb56-7c91-b9d6-dd2217dd4c47\siaganow-rmx2001-home.png`.
- Keterbatasan tes widget: widget test mencakup langsung perilaku splash/intro, Skip, Next, dan Start; integrasi root app terhadap first-launch dengan token kosong belum tervalidasi melalui test otomatis. Onboarding pada perangkat pengguna baru juga belum diverifikasi karena sesi yang sudah ada sengaja tidak dihapus atau diubah. Jangan menyatakan seluruh first-run QA perangkat lulus.

## Phase 18 — penyempurnaan komponen intro — 3 November 2026

- Komposisi khusus intro dirapikan: progres bernomor dan garis progres, ilustrasi ditempatkan pada bidang surface dengan batas halus, judul/deskripsi rata kiri dengan hirarki yang lebih jelas, dan tombol utama diberi ikon arah. Palet warna, font Poppins, aset/ilustrasi, tema aplikasi, serta layar lain tetap dipertahankan.
- `flutter test --no-pub`: seluruh 16 tes lulus. `flutter analyze --no-pub`: satu info lint lama di `lib/main.dart` sekitar baris 3662; tanpa error. Build Gradle debug berhasil; APK 226,048,583 byte. APK dipasang ulang dengan `adb install -r` di RMX2001 dan app berhasil diforeground tanpa menghapus data.
- QA visual perangkat untuk intro belum dilakukan: status onboarding pada HP sudah selesai akibat sesi yang telah ada, jadi startup tetap mengarah ke Home. Screenshot Home tersedia di workspace Codex. Preview golden sementara tidak dipertahankan karena test asset bundle/font tidak merepresentasikan tampilan perangkat.

## Phase 19 — affordance bayangan tombol — 3 November 2026

- Tema global `FilledButton`, `OutlinedButton`, dan `ElevatedButton` kini memberi bayangan bawah ringan saat aktif. Elevasi berkurang saat ditekan dan hilang saat disabled; bentuk, warna, ukuran, layout, serta desain halaman tidak diganti. TextButton dan IconButton mendapat elevasi lebih tipis tanpa tambahan latar sehingga tetap berbeda dari CTA utama.
- Tes Flutter: **16 lulus**. Analyzer tidak menemukan error; tetap ada satu info lint sebelumnya di `lib/main.dart` sekitar baris 3687. Build Android debug berhasil (`BUILD SUCCESSFUL`, APK baru berhasil dibangun; ukuran dicatat pada artefak lokal.) dan berhasil dipasang ulang pada RMX2001 dengan `adb install -r`, menjaga data aplikasi.
- Verifikasi visual khusus bayangan pada HP belum dilakukan; perangkat meluncur ke lock screen saat capture dan layar aplikasi tidak tertangkap pada sesi ini. Tidak menyatakan pemeriksaan visual bayangan lulus.
