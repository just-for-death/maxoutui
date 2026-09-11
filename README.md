# MaxOutUI for KOReader

**Version 1.1.3** — a manga-first KOReader UI built around [Suwayomi+](https://github.com/just-for-death/suwayomiplus).

MaxOutUI gives you a customizable home screen, bottom navigation, status bar, and deep online-manga modules so your Kindle (or any KOReader device) can be a primary manga reader — not just an offline book browser.

---

## Credits & lineage

MaxOutUI is a fork and rebrand of **SimpleUI for KOReader** by [Doctor Hetfield](https://github.com/doctorhetfield-cmd) ([simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)).

Huge thanks to the original SimpleUI work for the home screen architecture, navbar, module system, and UI patterns this project builds on.

| | |
|---|---|
| **Author** | [just-for-death](https://github.com/just-for-death) |
| **Based on** | SimpleUI by Doctor Hetfield |
| **Companion** | [Suwayomi+](https://github.com/just-for-death/suwayomiplus) · [MangaSync](https://github.com/just-for-death/mangasync) |

---

## What MaxOutUI adds (v1)

### Suwayomi home modules
Enable these in **MaxOutUI → Arrange Modules**:

| Module | Purpose |
|---|---|
| **Manga Library** | Your Suwayomi library covers, sorted by unread; tap resumes reading |
| **Recent Manga** | Last-read online manga from Suwayomi history |
| **New Chapters** | Library updates / newly fetched chapters |
| **Categories** | Pill buttons for Suwayomi library categories |
| **Manga Status** | Total / unread / last-synced summary cards |

### Quick actions
- **Continue Reading** — jumps into the next unread chapter via Suwayomi+
- Manga Library, Sources, Updates, Downloads, Pinned Manga

### Classic SimpleUI strengths (kept)
Home screen modules, bottom navbar, top status bar, wallpaper, icon packs, reading goals/stats, collections, TBR, presets, onboarding.

Internal filenames use the `mui_*` prefix. Settings keys remain `simpleui_*` so existing Kindle settings keep working after the rename from SimpleUI.

---

## Requirements

- [KOReader](https://github.com/koreader/koreader)
- Recommended: [Suwayomi+](https://github.com/just-for-death/suwayomiplus) + a [Suwayomi Server](https://github.com/Suwayomi/Suwayomi-Server)
- Optional: [MangaSync](https://github.com/just-for-death/mangasync) for offline CBZ → server progress sync

---

## Install

1. Copy this folder to:

```text
<koreader-root>/plugins/maxoutui.koplugin/
```

2. Restart KOReader.
3. Open **MaxOutUI** from the main menu (or the bottom bar tab).
4. Arrange home modules and enable the Suwayomi rows you want.

If you previously used `simpleui.koplugin`, remove that folder so only MaxOutUI loads.

---

## Suwayomi+ pairing

| In MaxOutUI | Calls Suwayomi+ |
|---|---|
| Continue Reading | `continueReading()` |
| Manga Library module | library fetch + `resumeMangaStream()` |
| New Chapters | `showUpdates()` / feed entry |
| Categories | `showLibrary()` / category filter |
| Pinned Manga | `suwayomi://manga/<id>` virtual URIs |

Online-first: streaming is the default chapter open path in Suwayomi+; downloads are secondary.

---

## License

Same spirit as upstream SimpleUI / KOReader plugin conventions. See `LICENSE` in this repo.
