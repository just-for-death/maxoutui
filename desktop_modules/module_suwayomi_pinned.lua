-- module_suwayomi_pinned.lua — MaxOutUI
-- Homescreen cover row for pinned Suwayomi manga (and local pins).
-- Tap uses the same Resume / Browse chooser as the Pinned Manga widget
-- (via homescreen openBook → Manga.openPinnedManga).

local _ = require("mui_i18n").translate
local RowRenderer = require("desktop_modules/mui_book_row")
local Manga       = require("desktop_modules/module_manga")

local M = RowRenderer.makeModule{
    id          = "suwayomi_pinned",
    name        = _("Pinned Manga (Suwayomi)"),
    label       = _("Pinned Manga"),
    default_on  = false,
    is_book_mod = true,
    has_covers  = true,
    max_items   = 999,
    paged       = true,
    -- Separate cache from the legacy pinned_manga book-row module.
    cache_key   = "_suwayomi_pinned_fps",
    getFileList = Manga.getPinnedMangaList,
    extra_menu_items_before = Manga.arrangeMenuItems,
    reset = function()
        RowRenderer.reset()
    end,
}

return M
