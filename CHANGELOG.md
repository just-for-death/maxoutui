# Changelog

All notable changes to SimpleUI will be documented in this file.

## [v2.6.0] - 2026-08-14

### Added
- **Suwayomi Integration Quick Actions** (`sui_quickactions.lua`):
  - Added 5 dedicated Quick Actions: **Recent Manga**, **Manga Library**, **Manga Sources**, **Manga Updates**, and **Manga Downloads**.
  - Added **Pinned Manga** Quick Action (`pinned_manga`) that opens a clean full-screen menu of all pinned online and local manga.
  - Robust KOReader module instance lookup (`_getSuwayomiInstance()`) querying both `FileManager.instance._modules` and `ReaderUI.instance._modules`.

- **Virtual Pinned Manga & Title Resolution** (`desktop_modules/module_manga.lua`):
  - Dual storage persistence (`ReadCollection` + `SUISettings`) allowing users to pin virtual Suwayomi online manga (`suwayomi://manga/id`) alongside local `.cbz`/`.pdf` files.
  - Custom title resolution (`getPinnedMangaTitle`) displaying real manga names (*One Piece*, *Gakuen Babysitters*, etc.) instead of raw URI strings.

### Changed
- Refined home screen layout by moving Suwayomi navigation into bottom bar Quick Actions.

## [v2.5.0] - 2026-08-14

### Added
- **Recent Manga (Suwayomi) Home Module** (`desktop_modules/module_suwayomi_history.lua`):
  - Fetches online manga reading history asynchronously from Suwayomi server GraphQL API.
  - Automatically loads and decodes cover thumbnails via Suwayomi's `ThumbnailCache` (`.bb` format) with fallback text placeholder cards.
  - Background cover prefetching (`prefetchThumbnailsAsync`) and auto-refresh on history update.
  - Tapping any cover streams the chapter or opens the full Suwayomi History feed.

- **Pinned Manga Home Module & Library Action** (`desktop_modules/module_manga.lua`):
  - Dedicated KOReader collection (`"Pinned Manga"`) for user-selected manga and books.
  - Adds **"Pin Manga" / "Unpin Manga"** hold-on-book dialog button to Library file browser and Search results.
  - Paginated cover row module (`pinned_manga`) with full Arrange/reorder support.

- **Recent Manga Quick Action** (`sui_quickactions.lua`):
  - New bottom-bar Quick Action descriptor (`recent_manga`) that opens the Suwayomi History screen directly.

### Changed
- Registered `suwayomi_history` and `pinned_manga` in `moduleregistry.lua` and `module_book_rows.lua`.
- Preloaded new modules in `main.lua` and added `sui_pinned_manga` file dialog button cleanup on teardown.
- Implemented robust 3-stage plugin resolution (scanning `package.loaded` and `package.path` for `suwayomiplus.koplugin`) for reliable inter-plugin communication.
