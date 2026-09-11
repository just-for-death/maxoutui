# Changelog

All notable changes to MaxOutUI will be documented in this file.

## [v1.1.5] - 2026-09-11

### Changed
- **Pinned Manga Title**: Card labels in the Pinned Manga row now display the manga title instead of defaulting to `"Pinned"`.
- **Compact Bottom Bar**: Made bottom navigation bar slightly smaller and sleeker (~14% height reduction, scaled icons, text, and margins) while maintaining comfortable touch targets.
- **MUI Wallpapers Directory**: Renamed wallpaper asset directory from `sui_wallpapers/` to `mui_wallpapers/` with full backwards-compatibility fallback.

### Fixed
- **Card and Label Overlaps**: Fixed text overflow in `RowRenderer` cards by enforcing `max_width = cw` and `truncate_with_ellipsis = true`, preventing long titles and chapter names from colliding with adjacent cards.
- **Negative Gap on Cover Scale**: Clamped card gap calculation to prevent negative spacing when scaling up covers.
- **E-Ink Wallpaper Ghosting**: Eliminated residual gray shadows when switching tabs or pages with an active wallpaper by promoting repaints to `"flashui"`.
- **Suwayomi+ Modules Standardization**: Standardized `suwayomi_library`, `suwayomi_updates`, and `suwayomi_history` on `RowRenderer` architecture with swipe pagination, unified cover caching, and chapter name formatting.

## [v1.1.4] - 2026-09-11

### Changed
- Shifted **Auto Download** from a homescreen desktop module to a dedicated Quick Action (`suwayomi_auto_download`) for Quick Action rows and bottom bar.
- Unregistered auto-download module from homescreen module registry.

### Added
- Dedicated Quick Action logo/icon: `icons/manga_auto_download.svg`.
- Quick Action window (`sui_win_auto_download_manga`): displays tracked manga covers with mode badges, tap to open manga, hold for options (Missing/Latest, Download now, Remove), top actions to add manga from library, download all now, or manage in Suwayomi+.

## [v1.1.3] - 2026-09-11

### Fixed
- Auto Download covers: decode SWTHUMB1 `.bb` via `ThumbnailCache.loadDecoded` and
  prefetch missing thumbs (same path as Manga Library).
- Pinned manga cover lookup prefers the shared `{ variant = "thumbnail" }` cache key.

## [v1.1.2] - 2026-09-11

### Added
- Homescreen module **Auto Download (Suwayomi)** (`suwayomi_auto_download`): manage
  manga with Missing / Latest modes; tap opens actions, hold changes mode or
  removes; menu adds from library and syncs downloads.

## [v1.1.1] - 2026-09-11

### Added
- Dedicated Suwayomi+ Quick Action icons (`manga_*.svg`): continue, library, recent,
  sources, updates, downloads, pinned, and pin/unpin — no more reused generic icons.
- Homescreen module **Pinned Manga (Suwayomi)** (`suwayomi_pinned`): cover row of
  pins; tap opens the same Resume / Browse chooser as the Pinned Manga widget.

### Changed
- Suwayomi Quick Actions now point at the new manga-specific icons in `mui_config`.

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
