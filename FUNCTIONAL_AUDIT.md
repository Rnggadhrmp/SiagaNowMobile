# SiagaNow Mobile and Laravel API Audit

Audit date: 30 October 2026. This records the code available before implementation changes. The Flutter repository is this workspace; Laravel is `C:\College\SiagaNow`. The initial backend inspection was read-only. Database structure was checked from migrations and the supplied implementation status; the live database was not reachable during the initial audit. Current implementation and verification state is recorded in [IMPLEMENTATION_PROGRESS.md](IMPLEMENTATION_PROGRESS.md).

| Feature / screen | Existing implementation | API endpoint used | Database table(s) | Status | Required changes |
|---|---|---|---|---|---|
| API client / config | `lib/main.dart` has one `ApiService`, but duplicates only GET/JSON POST, uses compile-time URL, has no connection/JSON parsing abstraction or typed errors; base defaults emulator/Web | All `/api/*` | None | Partial | Normalize base URL, timeout connect/receive, structured errors, guard invalid JSON, support query/multipart, typed parsing; keep LAN address solely in dart-define |
| Session restore / profile | Secure token read and GET `user`; any failure deletes token, profile name held locally | `GET /api/user` | `users`, `personal_access_tokens` | Partial | Explicit 401 handling vs transient failures, typed user, central auth state |
| Login | Bottom sheet calls login with `identifier`/`password`, stores token; does not re-fetch profile; limited errors | `POST /api/login`, then intended `GET /api/user` | `users`, `personal_access_tokens` | Partial | Typed validation/auth errors, fetch profile, persist only after successful profile check |
| Registration | No mobile form. Backend supports `name`, `phone`, `email`, `password`, `password_confirmation` | `POST /api/register` | `users`, `personal_access_tokens` | Missing mobile flow | Add fields exactly as validated; show field errors; no backend contract change |
| Logout / auth guard | Calls logout, clears token even on failure; authenticated report screen is gated in UI | `POST /api/logout`; `GET /api/user` | `personal_access_tokens` | Partial | Centralize clear/session state; block private requests on guest/invalid token |
| Home / weather | Calls `/home`; renders weather and statistics; lacks news and separate warning fetch; demo fallback local and labeled | `GET /api/home`; available `GET /api/weather-forecast`, `/api/weather-warning`, `/api/news` not called | `weather_warnings`, `disaster_events` (no live stats source) | Partial | Use available public endpoints, typed actual/simulation/unavailable states, refresh/error states |
| Shelter list / map | Calls `/shelters`, but no query/search; map is static placeholder; simulation list labeled | `GET /api/shelters` (supports `q`) | `shelters` | Partial | Search with debounce/submit, show source/status/verified timestamp, accurate empty/error state; no route fabrication |
| Report submission | Auth-gated form posts supported scalar fields; coordinates prefilled with Padang example; duplicate guard via sending state; no response ID shown; no history | `POST /api/reports` | `disaster_reports`, `users` | Partial | Remove silent example coordinates, validate coordinate range, make location explicit/editable, display returned ID/status, history and ownership-backed empty state |
| Report attachments | Backend accepts up to 5 private local files (JPG/PNG/WEBP/MP4/WEBM, 10 MB each), client has no picker/multipart | `POST /api/reports` multipart field `evidence[]` | `disaster_reports.evidence_paths` | Partial | Add picker and multipart only if dependency/platform support allows; preserve private storage and backend validation |
| News | No mobile news screen/content | `GET /api/news` available, simulation or unavailable | None (config data only) | Missing | Add transparent list/detail state and navigation |
| Emergency services | More page opens Padang PCC 112 dialer; labels local scope and other regions' guidance | External tel:112 | None | Working, scoped to Padang | Retain scope and dialer failure handling |
| Other services | Donation / Keluarga Siaga presented as nonfunctional informational cards | None | No donation transaction / family tables | Honest unavailable | Keep unavailable status clear |
| Navigation / actions | 4 tabs; quick cards have no action; no profile/history/news/weather screens; login/logout app bar | As above | As above | Partial | Connect all existing actions to intended screen or clear unavailable state |
| Tests | One widget test checks initial loading only | None | Laravel tests cover mobile API/report per code inventory | Partial | Add client parsing/auth/navigation/form tests and run available Flutter/Laravel suites when safe |
| Database / backend contract | Laravel routes include public home/weather/news/shelter/warning and Sanctum `mobile` protected user/logout/report endpoints. Report owner filter present. Migration defines report fields/status/evidence path. | Routes in `C:\College\SiagaNow\routes\api.php` | `users`, `personal_access_tokens`, `shelters`, `weather_warnings`, `disaster_events`, `risk_assessments`, `disaster_reports` | Available per inspected code | Additive nullable casualty migration was applied to the local `siaganow` MySQL database; see progress record |

## Audit notes

- Backend authentication payloads and field names were verified from `AuthController`; registration is supported with email, phone, name, password confirmation.
- Report fields and validation were verified from `DisasterReportController`; attachments are stored on Laravel's private `local` disk. At baseline, omitted casualty counts were persisted as zero. The implementation now preserves omitted values as NULL and explicit zero as 0, covered by backend feature tests and an additive migration.
- Shelter API returns database or simulation `data_type`, `source`, and shelter verification fields; query parameter `q` is supported.
- `/api/home` includes weather, statistics, and warning status `unknown`; separate warning check endpoint exists. News endpoint returns demonstration items only while demo mode is enabled.
- Backend migrations inspected: shelter, weather warning, event, risk assessment, disaster reports, and Sanctum personal access tokens. The supplied status records 16 MySQL tables and 11 applied migrations. The live target was subsequently verified as local MySQL schema `siaganow`; the additive migration is applied and migration status is recorded in the progress document.
- The user-provided project path `D:\laragon\www\SiagaNowMobile` differs from the active workspace path `C:\College\SiagaNowMobile`. Work will target the active workspace.

## Current verification update — 1 November 2026

The table above is a baseline snapshot from before the integration work. The following results were verified afterward:

| Check | Exact result | Scope / limit |
|---|---|---|
| Android build diagnosis | The default build failed before compilation in Gradle's Windows `WEPollSelectorImpl`: `java.io.IOException: Unable to establish loopback connection`, caused by `java.net.SocketException: Invalid argument: connect` in `PipeImpl`. A standalone JDK 25 `Selector.open()` reproduced it with the inherited temp directory and succeeded after setting `TEMP` and `TMP` to a short workspace path. | Environment issue, not an app compile error. The Gradle logs also exposed an IDE-held project build lock; the final build used an isolated Gradle project cache to avoid interrupting that IDE import. |
| Android debug APK | `assembleDebug` succeeded. APK: `C:\College\SiagaNowMobile\build\app\outputs\apk\debug\app-debug.apk` (161,998,457 bytes). Installed and launched successfully on `emulator-5554`, model `sdk_gphone64_x86_64`, Android API 37. | Emulator smoke run only; no physical-device test. |
| Flutter Home → Laravel | The running Android app loaded `/api/home` from a temporary Laravel server configured to a disposable SQLite file under the mobile workspace. The Home screen showed a 27° BMKG forecast labeled with BMKG source/location and update time; warning state remained unknown and statistics were labeled training data. | Public API/UI flow verified. This run did not query the live MySQL database. |
| Shelter search → Laravel | The app loaded `/api/shelters`; entering `Kuranji` filtered the displayed response to one result, `Contoh Shelter Kuranji`. The result was explicitly labeled simulation / not verified. | Public API/UI flow verified against the isolated SQLite-backed server's simulation response. Interactive map and routing remain unavailable. |
| Authentication / report submission | No authorized test account or credentials were present in project artifacts. Login, secure token persistence, authenticated profile, logout, report creation, report-history ownership, and Flutter attachment upload were not attempted. | Do not treat Laravel's automated tests as Flutter end-to-end verification. The API contract and automated SQLite tests cover token protection, ownership, persistence, and private-disk attachment handling; no authenticated Flutter record was created. |
| Data safety | The emulator API server was stopped after the smoke check. Its disposable SQLite database was separate from local MySQL; the live MySQL rows were not read or modified during this verification. | Existing MySQL records remain unaltered by this emulator run. |

## Phase 2 — real MySQL integration update — 1 November 2026

| Check | Verified result | Scope / limit |
|---|---|---|
| Laravel environment and database | `.env` values were read without displaying credential values: `APP_ENV=local`, `DB_CONNECTION=mysql`, `DB_DATABASE=siaganow`, host `127.0.0.1`, port `3306`. The listener was initially stopped. Existing Laragon MySQL 8.4.3 was started with its configured `my.ini` and existing `mysql-8.4` data directory. `php artisan migrate:status` then connected to MySQL and showed all 12 migrations `Ran`. | No migrations were run. No users or reports were added, changed, or deleted. Database credentials were neither shown nor copied into Flutter. |
| Emulator API base | The installed APK used Flutter's Android default `http://10.0.2.2:8000/api`. `SIAGANOW_API_URL` remains configurable with `--dart-define`. Laravel was bound on `0.0.0.0:8000` using its local `.env` configuration. | The public endpoint calls reached this Laravel process, which was configured to MySQL `siaganow`. |
| Home from emulator / API | The app requested `/api/home`; Laravel logged the request. Direct response was 200, weather `data_type=actual`, source `BMKG`, location Belakang Pondok, Padang Selatan; statistics were `simulation` and warning `unknown`. The emulator Home screen rendered the BMKG forecast. | Weather comes from BMKG; Home statistics are explicitly training data. |
| Shelter search from emulator / API | The app requested `/api/shelters`; entering `Kuranji` displayed `Contoh Shelter Kuranji` as simulation / not verified. On MySQL, `SELECT COUNT(*) FROM shelters` returned 0; the endpoint used its configured simulation fallback and returned one matching item. | This verifies the app-to-Laravel path and MySQL-backed shelter lookup/fallback; it does not establish that any verified shelter data is present. |
| Guest access and database preservation | Guest `GET /api/reports` returned 401. Final MySQL counts were 1 row in `disaster_reports` and 0 rows in `shelters`. No report POST or other data-changing request was issued. | Only public/read-only endpoint and count checks were performed. |
| Authentication, registration, report flow, history, attachments | Laravel's login contract is `identifier` + `password`; registration accepts `name`, `phone`, `email`, `password`, and `password_confirmation`. Flutter sends these fields and the report multipart field `evidence[]`. No authorized test credentials were supplied or documented, so no login, registration, token/profile/logout, report write, history ownership, or upload test was attempted. | A test account is required to continue these authenticated tests. No credentials or account were fabricated. The backend feature suite previously verified report ownership, persistence, and private-disk attachment validation on isolated SQLite. |
| Runtime state | Android emulator `emulator-5554` (AVD `Medium_Phone_API_37.0`) is connected. The local MySQL process and Laravel server are left running to support further emulator checks. | No physical-device verification was performed. No backend source files were changed in this Phase 2 run. |

## Phase 3 — Flutter frontend and emulator audit — 1 November 2026

The Phase 3 Figma reference is `APK-BENCANA`, mobile page `Mockup Mobile` (node `1:3`). Its top-level frames include Beranda (`1:1380`), Berita (`1:1405`), Cuaca (`47:410`), Laporkan Bencana (`1:1515`), Daftar Kontak Darurat (`1:1616`), Rute Evakuasi (`1:1651`), Profil (`1:1699`), and Login (`456:806`). Screenshots were retrieved for Beranda, Berita, and Rute Evakuasi. `get_design_context` returned context for Beranda, Cuaca, Laporkan Bencana, and Profil. Later per-node screenshot requests timed out. The app now uses the mobile mint/green palette, compact home information cards, warning state, latest-news card, preparedness shortcut, weather card, and bottom navigation. Original photography, Poppins typography, and the complete Figma layouts are not fully reproduced; the primary visual redesign in this pass is Home.

### Changes and navigation

- Home renders BMKG weather and interval forecasts from `/api/home`; news comes from `/api/news`; warning `unknown` remains explicit; training statistics carry their supplied training-data attribution; simulation news is labeled. The news list opens an in-app detail view for each returned item.
- The Home weather card opens a detail screen using the same actual response, including the source, region, interval forecast, and unknown warning state. PCC 112 in More opens a contact-details screen; that screen exposes only the Padang service already identified by the project and explicitly says family contacts are not stored.
- Shelter search uses `/api/shelters?q=...`; markers and routes are not simulated as real locations. The map panel explicitly says interactive mapping and safe routes are unavailable.
- Login/register use the existing `/login` and `/register` contracts. The login/register entry had a root-context bug: `showModalBottomSheet` was called above `MaterialApp`, producing `No MaterialLocalizations found` on guest tap. `GlobalKey<NavigatorState>` and `GlobalKey<ScaffoldMessengerState>` now provide the correct contexts. A fresh emulator run opened both forms and produced no new Flutter error logs.
- The report form supports the existing multipart `evidence[]` API and accepted types/limits in the client. Guest validation runs before the auth gate, and the emulator displayed empty coordinate and description errors. No report write was attempted. The existing authenticated history path continues to call owner-filtered `/reports`.
- Profile access is available from the header and More menu. Logout still calls `/logout` and clears the locally stored token; those authenticated actions were not tested because no authorized account was available. The header/avatar and More routes opened in the guest state.
- PCC 112 in More opens the local Padang dialer only; donations and Keluarga Siaga remain clearly unavailable. A mobile risk result is not fabricated because the backend only exposes a web controller, not a mobile risk API. Contacts, hazard layers, and evacuation routes have no available mobile APIs.

### Phase 3 verification record

| Check | Exact result | Limit |
|---|---|---|
| `flutter pub get` | Completed as part of analyze/test/build; current lockfile dependencies resolved. Pub reported 23 packages with newer versions incompatible with present constraints. | No dependency upgrade was made. |
| `flutter analyze` | **No issues found.** | Current mobile workspace. |
| `flutter test` | **5 passed, 0 failed** (4 model tests, 1 widget loading test). | Does not cover authenticated end-to-end API calls. |
| Android debug APK | **Build succeeded** with `flutter build apk --debug`. Final APK: `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk`; installed and launched on `emulator-5554`. Build used a short workspace `.tmp` path for `TEMP`/`TMP`, avoiding the Windows inherited temp-path issue recorded earlier. | Emulator only; no physical-device test. |
| Home integration | Emulator showed 27°C, Hujan Ringan, BMKG source and the Belakang Pondok/Padang Selatan location from the live Laravel API. The API response included actual BMKG forecasts. Warning status was `unknown`; Home statistics were explicitly labeled as training data. | Public GET requests only. Laravel was reachable from emulator at `10.0.2.2:8000`. |
| Weather / emergency navigation | Tapping the Home weather card opened weather details; tapping PCC 112 from More opened the contacts detail page. | The dial action itself was not triggered. |
| News | `/api/news` returned simulation items. The app displayed its simulation banner; tapping an article opened its detail screen. | Not an official live-news feed. |
| Shelter search | Searching `Kuranji` displayed `Contoh Shelter Kuranji` with `Simulasi · bukan shelter terverifikasi`. | `shelters` MySQL table has zero rows; fallback is simulation. No safe route or interactive map was tested. |
| Login/register UI | Login form opened; blank login showed required-field validation. Register mode showed name, email, and confirmation fields. Fresh post-fix tap produced **0** Flutter error entries in the cleared logcat filter. | No authorized credentials; no login/registration/network write submitted. Token persistence, profile retrieval, and logout were therefore not verified. |
| Report form | Blank guest submission showed field errors including missing coordinates and description length. Attachment picker is implemented for the existing backend-supported file types. | No authenticated submission or upload; no test report created. |
| Database preservation | Read-only query after the checks returned `disaster_reports = 1`, `shelters = 0`, matching the prior live MySQL counts. | No API write, schema migration, or database mutation was performed in Phase 3. |
| Laravel suite | Prior successful result remains **23 tests, 138 assertions**; not rerun in Phase 3. | Laravel source was not touched. |

### Remaining unverified or unavailable

- Authorized login, secure token persistence on successful login, authenticated `/user`, logout, report persistence/receipt, report ownership from Flutter, and actual attachment upload need an authorized test account. No account or report was created.
- Interactive maps, verified shelter detail, safe routing, location-specific warning lookup from a selected point, official current incident data/news, risk assessment through a mobile API, donation transactions, and Family Siaga are unavailable in the current mobile API/data.
- Non-Home screens were kept functional and consistently themed, but Profile, Login/Register, News, map, and Report are not full pixel-level reproductions of every Figma asset/layout. No physical Android device was tested.

## Phase 4 — Figma assets, visual pass, and emulator verification — 1 November 2026

### Figma inspection and visual comparison

The Mobile page metadata was inspected for all 22 top-level frames: Beranda (`1:1380`), Berita (`1:1405`), Cuaca (`47:410`), Laporkan Bencana (`1:1515`), Daftar Kontak Darurat (`1:1616`), route variants (`1:1651`, `277:186`, `286:674`, `293:813`), Profil (`1:1699`), Daftar (`449:639`), Login (`456:806`), donation frames (`111:201`, `1:1782`, `1:1807`, `1:1856`), Keluarga Siaga (`383:378`), Status Aman (`390:491`), and remaining contact/status/report states (`390:545`, `403:760`, `404:823`, `404:869`). Figma-only family, donation, success, and evacuation examples were not turned into claimed backend functionality.

Screenshots/design context from preceding work were visually compared with the current emulator for Home, News, weather, report, login/register, contacts, profile, and route states where screenshots were available. In this pass, new emulator captures were reviewed for Home, the report form, the shelter/map tab, and News. Home now uses the Figma wave header, exported flood-news image, warning artwork, weather illustration, landscape footer, green card hierarchy, and Poppins. The report retains its data-entry form and omits the Figma map graphic because it contains unverified example markers. The shelter/map state explicitly says interactive mapping and safe routes are unavailable. News uses original Figma flood photographs only for API items labeled simulation. This is a screen-composition and asset-alignment pass, not a claim of pixel parity for all 22 frames.

### Original assets and typography

The following exported Figma images are registered in `pubspec.yaml` and used by Flutter:

- `assets/images/header_waves.png` — shared header waves.
- `assets/images/landscape_background.png` — Home landscape footer.
- `assets/images/news_flooded_home.jpg` and `assets/images/news_flood_damage.jpg` — Home/News imagery shown only with simulated news.
- `assets/illustrations/home_flood_warning.png` — Home warning state illustration.
- `assets/illustrations/weather_sun_cloud.png` — Home weather card illustration.
- `assets/illustrations/login_shield_landscape.png` — Login and registration sheet illustration.

Poppins Regular, Medium, and Bold are bundled under `assets/fonts/` and applied app-wide. The accompanying SIL Open Font License 1.1 is included at `assets/licenses/Poppins-OFL.txt`; the upstream Poppins project identifies its font license as OFL: [Poppins license](https://github.com/itfoundry/Poppins/blob/master/OFL.txt). Generic Figma SVG exports remain under `assets/figma/` for reference; only the image/font files listed above are registered as app assets. The Figma raster map with sample shelter pins was not included in product UI.

### Current implementation and verified interactions

| Area | Phase 4 result | Verification boundary |
|---|---|---|
| Home | Figma art and typography integrated while retaining existing Home API weather, forecast, warning, statistics, and news. | Emulator showed the API-provided 27°C BMKG forecast. Warning was unknown; statistics and sample news remained explicitly labeled. |
| News | Figma flood images are used for simulation cards; API text/source and simulation labels remain visible; item navigation remains active. | Emulator News tab loaded the simulation response and rendered both local images. |
| Weather | Original sun/cloud illustration is used in the Home card; detail screen remains driven by the existing Home response. | Existing navigation was retained; this pass did not query a new weather endpoint. |
| Report | Existing report fields, validation, date/time selection, device/manual location, evidence picker, and submit logic were preserved. Coordinates remain empty unless supplied by device/user. | Emulator opened the report form. No POST was sent; report-history ownership was not independently inspected in this pass. |
| Profile/session | The emulator installation already contained a stored session. After installing the new APK over the app, session restoration completed and the Profile screen rendered from authenticated `GET /api/user`. | This verifies restoration/profile retrieval for the pre-existing local session only. It was not established as an authorized test account; no credentials were entered and no logout or data write was issued. |
| Shelters/map | Search tab continues to call the existing shelter endpoint and labels simulation results as unverified; no map pins/routes are fabricated. | Emulator displayed `Contoh Shelter Kuranji` and another simulation item. The established database audit reported zero MySQL shelter rows; do not use these results as safe-zone guidance. |
| Other Figma states | Donation/payment, Family Siaga, safe-status broadcast, and saved-report sample states remain unavailable or informational because corresponding mobile API/data support is absent. | No fabricated transaction, family, report receipt, emergency contact list, shelter verification, or route was added. |

### Exact Phase 4 verification

| Check | Result | Scope |
|---|---|---|
| `flutter pub get` | **Succeeded**; dependencies resolved. Pub reported 23 newer versions incompatible with current constraints. | No dependency versions were upgraded. |
| `flutter analyze --no-pub` | **No issues found.** | Final Phase 4 source. |
| `flutter test --no-pub` | **5 passed, 0 failed.** | Four model parsing tests and the loading widget test. |
| `flutter build apk --debug` | **Succeeded.** Final APK: `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk` (185,643,302 bytes). | Debug APK; Windows build used workspace `.tmp` for `TEMP` and `TMP`. |
| Android install and launch | `adb install -r`: **Success** on `emulator-5554` (`sdk_gphone64_x86_64`, API 37); app launched. | Emulator only; no physical-device test. Filtered `flutter:E` and `AndroidRuntime:E` logcat checks returned no errors during inspected navigation. |
| Emulator navigation/screens | Home, News, report form, profile, and shelter/map tab were opened and screenshots reviewed. News rendered the new local Figma photos. | No authenticated write was initiated. |
| Laravel/MySQL writes | No report, registration, logout, attachment upload, migration, or other data-changing request was issued in this Phase 4 pass. | Existing Laravel result remains the previously verified 23 tests / 138 assertions. MySQL counts were not re-queried during this visual/build pass. |

### Remaining verification and design limitations

- No fresh login, registration, logout, report submission, attachment upload, or report-ownership check was performed. The emulator's pre-existing session is not treated as an authorized test account. Report history ownership remains supported by the existing API contract and prior Laravel feature tests, but is not claimed as newly verified end to end here.
- The API currently supplies simulation shelters/news and no interactive map, verified shelter points, safe routes, donation service, Family Siaga, or mobile risk endpoint. The app continues to disclose those limits.
- Several Figma-only frames contain demonstration content and are not reproduced as real user data. Full pixel parity across all 22 frames and physical-device verification remain incomplete.
- The Android build is sensitive to the inherited Windows temp directory in this environment. The earlier diagnostic identified `Unable to establish loopback connection` / `SocketException: Invalid argument: connect` during Java selector setup. Setting both `TEMP` and `TMP` to the short workspace `.tmp` directory allowed Flutter analysis and the final APK build to complete.

## Phase 5 — missing features, integration, and Android verification — 1 November 2026

### Implemented

- Added a Family Siaga MVP connected to owner-scoped Laravel APIs: one family group per account; group rename/delete; member add/edit/delete; and emergency phone storage. Invitations, location sharing, and alerts are not represented as available.
- Added risk request and history screens backed by the existing `risk_assessments` model/table. The form submits only existing supported input fields. The server stores requests as `pending` with limitations; the app displays no score unless the API provides one.
- Added an honest donation information screen. No verified program, organization, official channel, payment gateway, or in-app payment is configured; no demo campaigns or transactions are presented as real.
- Added shelter result details showing source and verification state, explicit simulation warning, and unavailable route/capacity details. Removed the generic demo badge from More.
- Fixed the analyzer/build source defect: `AppBarTheme` has no `flexibleSpace` parameter. Removed the unsupported theme property; page-specific Figma artwork remains in use.
- Added the additive migration `2026_11_01_000001_create_family_groups_and_members_tables.php` for `family_groups` and `family_members`. Family CRUD and risk list/create APIs use authenticated mobile routes. Risk uses its existing table. No backend reset or destructive data operation was performed.

### Exact verification

| Check | Result | Boundary |
|---|---|---|
| `flutter pub get` | Succeeded; 23 newer package versions remain outside current constraints. | No package upgrades. |
| Dart format | `dart format lib/main.dart` completed. | One Dart source file. |
| `flutter analyze --no-pub` | **No issues found.** First run caught unsupported `AppBarTheme.flexibleSpace`; after removal, analysis passed. | Current Flutter source. |
| `flutter test --no-pub` | **5 passed, 0 failed.** | No authenticated integration flow claimed. |
| Android debug APK | **Build succeeded** at `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk` (185,682,069 bytes). Gradle `assembleDebug` completed in 86.5 seconds with `TEMP`/`TMP` set to workspace `.tmp`. | Java restricted-native-access warning was non-fatal. |
| Emulator | `adb install -r` returned **Success** on `emulator-5554`; app launched. Screenshots confirmed Home (BMKG 27° weather, simulation-labeled news, training statistics, unknown warning), More (Family Siaga/Risk/Donasi destinations), and Donasi informational state. Filtered logcat showed no Flutter/Android fatal exception. | `sdk_gphone64_x86_64`, API 37; no physical device tested. Family/risk authenticated screens were not opened on the existing account. |
| Public API smoke | `/api/home` **200**; `/api/news` **200**; `/api/shelters?q=Kuranji` **200**; guest `/api/reports` **401**. | Read-only GETs against local Laravel server. |
| Laravel suite | **28 passed, 0 failed, 172 assertions** via `php vendor/bin/phpunit --do-not-cache-result --testdox --no-coverage`, with `LOG_CHANNEL=stderr`. | In-memory SQLite per PHPUnit config. The initial plain run hit sandbox write denials for Laravel log/cache files; the successful run avoided those writes. |
| Routes/migration | Phase 5 route check: **21 API routes**; additive family migration status **Ran**. | Existing migration history retained. |
| MySQL preservation | Read-only counts after migration: `family_groups = 0`, `family_members = 0`, `disaster_reports = 1`, `shelters = 0`. | No Flutter family, risk, or report write occurred; existing report row remains. |

### Not verified or unavailable

- No authorized test credentials were provided or documented. The emulator's pre-existing signed-in account was left untouched. New login/token persistence, authenticated profile/logout, report submit/history ownership, family CRUD, risk submit/history, and attachment upload were not exercised through Flutter. Backend feature tests independently cover authentication, family authorization/validation, pending risk persistence/ownership, report ownership, and private attachment storage/validation on isolated SQLite.
- No verified shelter rows, interactive map, safe-route service, verified hazard-scoring dataset, live donation program/payment integration, family location-sharing, or emergency notifications are available. The relevant pages disclose these limitations.
- Existing exported assets and Poppins styling were reused; complete pixel parity across all Figma frames was not verified.

## Phase 6 — core stabilization and regression checks — 1 November 2026

### Family Siaga runtime report

- Reproduced the current route on `emulator-5554` by opening Keluarga Siaga from More; it loaded the API-backed empty-group state. Reopened it from the Home shortcut after correcting that shortcut to use the actual Family page. Neither attempt produced the reported `_dependents.isEmpty` assertion. The filtered Flutter logcat contained no Flutter exception/stack trace, so the reported assertion's root cause is **not established** and no exact root-cause fix is claimed.
- Inspected Family navigation and its asynchronous load/mutation callbacks. Added `mounted` guards before starting/finishing loads, mutations, and login continuation so callbacks do not update state after route disposal. Added a mocked-API widget regression test for opening the page, loading the empty state, and navigating back.
- No family group/member create, edit, or delete was submitted. The MySQL family tables were previously verified empty. The emulator's pre-existing auth session is not treated as an authorized test account.

### Risk layout and navigation fixes

- Replaced the Home Keluarga Siaga “unavailable” dialog with navigation to the existing Family page.
- Expanded all risk dropdown fields to available width, shortened rainfall options to their supported category names, and made the device-location button label wrap inside a full-width button.
- Added mocked API layout coverage at **320×640** and **375×812 logical pixels**. The Risk form and dropdown fields rendered without Flutter layout exceptions at both viewports. This is widget-test coverage; only the default API 37 emulator viewport was available for device inspection.
- Added API client injection for an HTTP client and token reader so these widget checks use mock responses and make no real account requests or database writes.

### Figma inspection boundary

- Read metadata for all **22 top-level frames** on the Figma Mobile page. The current page includes Home, News, Weather, report, shelter/route, Profile, login/register, donation, and emergency-contact frames; the metadata does not provide dedicated Risk Assessment or Family Siaga top-level frames. Node `383:378` is named “Layanan Darurat,” rather than a family frame.
- Requested high-fidelity design context for the accessible emergency-services frame, but the Figma MCP context request timed out. Existing local exported assets and prior Phase 4 screenshot comparisons remain the design basis. This phase did **not** achieve full pixel-level reconstruction of every screen. The tested screens in this pass were Home, Weather detail, More, Donation, and Family empty state; other screens retain their earlier audit status.

### Exact Phase 6 verification

| Check | Result | Boundary |
|---|---|---|
| `flutter pub get` | **Succeeded**; 23 newer package versions remain incompatible with current constraints. | No package upgrade. |
| `flutter analyze --no-pub` | **No issues found.** | After lifecycle, navigation, and responsive updates. |
| `flutter test --no-pub` | **7 passed, 0 failed**: 4 model tests, 1 session-loading widget test, and 2 Phase 6 lifecycle/responsive tests. | Family and Risk tests use mocked HTTP responses. |
| `flutter build apk --debug` | **Succeeded**; Gradle `assembleDebug` completed in 36.4 seconds. APK `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk`, **185,683,103 bytes**. | `TEMP` and `TMP` pointed to workspace `.tmp`; Java restricted-native-access warning was non-fatal. |
| Emulator install and flows | `adb install -r` returned **Success** on `emulator-5554`. Home loaded, Weather detail opened, and the Family page opened from More and Home and displayed the empty state. Filtered logcat showed no Flutter assertion or Android fatal exception during Family navigation. | Android API 37 emulator only. No report/family/risk writes; no physical-device test. |
| Backend/database | No Laravel source, routes, migrations, or MySQL data changed in Phase 6. | Previous backend verification remains **28 tests / 172 assertions** on in-memory SQLite; it was not rerun because backend files were unchanged. |

### Remaining work

- Phase 8 later reproduced and fixed a Family Siaga create-dialog lifecycle defect; see the Phase 8 record below. The earlier Phase 6 attempt had only tested page navigation.
- Authenticated report submission/history/ownership, logout, Family CRUD, Risk submission/history, and attachment upload still require an explicitly authorized test account and safe test data. Current account data was not changed.
- Full screen-by-screen Figma reconstruction and screenshots for every screen remain incomplete. The available context tool timed out; there are no dedicated risk/family top-level mockup frames in the returned page metadata.
- Risk layout was tested at two viewport sizes in a mocked widget environment, not at two emulator viewport sizes. A real verified risk scoring service, verified shelter/routes, and official donation/payment integration remain unavailable.

## Phase 8 — Family Siaga crash reproduction and interactive map — 1 November 2026

### Family creation crash

- Reproduced the create flow with the new `Family creation posts the name and reloads the created group` widget test against an in-memory `MockClient`. The request was not sent to Laravel or MySQL.
- The first exception occurred during the dialog route's reverse transition, before the mocked POST completed: `A TextEditingController was used after being disposed.` The relevant pre-fix widget was the family-name `TextField` (`lib/main.dart:2260:18` at reproduction). The stack reached `ChangeNotifier.addListener` → `_MergingListenable.addListener` → `_AnimatedState.didUpdateWidget` → `StatefulElement.update` while Flutter rebuilt the transitioning dialog. A later scheduled callback also raised `RenderObject.getTransformTo: 'attached': is not true`, a cascade from the detached editable field. The full captured output is in the ignored local file `.tmp/family-create-crash.log`.
- Root cause: `_textDialog` owned a `TextEditingController` in `_FamilyPageState` and disposed it as soon as `showDialog` returned. The route had returned its result but had not finished its reverse animation; the dialog's `TextField` still depended on that controller. `_memberDialog` had the same ownership pattern for three controllers.
- Moved controller ownership into `_FamilyNameDialogState` and `_FamilyMemberDialogState`, where each controller is disposed with its dialog State. Added required/max-100-character family name validation. The exact reported `_dependents.isEmpty` assertion from the prompt did not appear in the captured reproduction; the create interaction instead exposed the controller/disposal exception above, followed by the detached-render-object assertion.
- Regression tests now cover opening/empty state/back navigation, valid create and reload, blank local validation, Laravel 422 validation, server 500 response, and navigating away/reopening to retrieve the created mock group. These verify client behavior and the mock API lifecycle; they do **not** verify Laravel persistence or an actual user account.

### Interactive map and shelter API

- Replaced the map placeholder with `flutter_map 8.3.2` and `latlong2 0.10.1`. Tiles use the configurable compile-time `SIAGANOW_TILE_URL`, defaulting to `https://tile.openstreetmap.org/{z}/{x}/{y}.png`. `flutter_map_cache 2.1.0`, `http_cache_file_store 2.0.2`, and `path_provider 2.1.6` provide persistent response caching using the server's cache directives and a 30-day stale fallback. The request identifies the app as `SiagaNowMobile/1.0`; attribution is displayed on the map and below it. The OSM tile URL, User-Agent, visible attribution, cache behavior, and prohibition on bulk/prefetch tile downloads follow the [OSMF tile usage policy](https://operations.osmfoundation.org/policies/tiles/) and [flutter_map's OSM setup guidance](https://docs.fleaflet.dev/tile-servers/using-openstreetmap-direct).
- On `emulator-5554` (Android API 37), the map loaded actual OSM tiles. A drag changed the visible geographic extent; tapping zoom-in increased the map detail. The explicit location button obtained a one-shot emulator-provided location and showed a blue user marker. Location is requested only after tapping that control; no continuous location subscription was added. This is emulator verification, not physical-device verification.
- The actual local API request `GET /api/shelters?q=Kuranji` returned HTTP 200 with `data_type: simulation` and a sample record (`is_simulated: true`), not a MySQL shelter. In the app it is labeled `Simulasi · bukan shelter terverifikasi` and is **not** rendered as a shelter marker. Client-side parsing rejects missing, non-finite, or out-of-range coordinates. No real shelter marker or official evacuation route was available to verify; tapping an address-only/simulation result gives an explicit no-verified-coordinates message.
- The map remains usable without a shelter record. Tile/cache errors have a visible fallback state. Search requests are guarded against overlap, and a unique actual result is focused only when it has valid coordinates. Because this API response was simulated, Phase 8 did not claim to verify result focus on a real shelter. Official evacuation routing and safe-zone data remain unavailable.
- During the first emulator pass, map construction surfaced `Unsupported operation: Cannot modify unmodifiable map`: the app had supplied the tile request headers as a `const` map, but `flutter_map` injects its User-Agent into that map. Changed the provider headers to a mutable map, rebuilt, and confirmed tiles then rendered. No Flutter or Android fatal errors were present in the post-fix filtered logcat check.

### Exact Phase 8 verification

| Check | Result | Boundary |
|---|---|---|
| `flutter pub get` | **Succeeded**; 24 newer package versions remain outside current dependency constraints. | Added only the map, cache, and direct path/coordinate dependencies. |
| `flutter analyze --no-pub` | **No issues found.** | Phase 8 source. |
| `flutter test --no-pub --reporter expanded` | **12 passed, 0 failed** (5 API model tests, 1 session-loading widget test, 5 family/navigation tests, 1 responsive Risk test). | Family create, validation, API errors, and persistence/reopen use mocked in-memory HTTP only. |
| `flutter build apk --debug --no-pub` | **Succeeded**; APK `C:\College\SiagaNowMobile\build\app\outputs\flutter-apk\app-debug.apk`, 187,365,372 bytes. | Windows `TEMP`/`TMP` set to workspace `.tmp`; Gradle emitted a non-fatal Java restricted-native-access warning. |
| Emulator install and map | `adb install -r`: **Success** on `emulator-5554`; OSM tiles, attribution, zoom, pan, current-location marker, and simulation-labeled search result were visually checked. | Android API 37 emulator. Family POST was not invoked against the existing unauthorised session. No physical device. |
| Backend and MySQL | No Laravel source, routes, migrations, or MySQL writes were made. | Prior backend test result remains **28 tests / 172 assertions** (isolated in-memory SQLite); not rerun because backend was unchanged. No new SQL count query was performed in Phase 8. |

### Remaining verification

- Family creation and persisted family retrieval have only been verified using the test's in-memory fake API. An authorized test account and safe test database were not available, so no emulator family write or real persisted-family read was made.
- Search focus on a real shelter marker cannot be verified until the API supplies an actual record with valid coordinates. The only returned result during Phase 8 was simulated.
- The emulator grants location permission and supplied a location fix; permission-denial and physical-device GPS behavior were not tested.
- Existing report submission/history ownership, session login/logout, and real backend integrations from earlier audit sections were outside this Phase 8 pass.
