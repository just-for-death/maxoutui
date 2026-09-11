-- module_suwayomi_pinned.lua — MaxOutUI
-- Deprecated duplicate module; canonical Pinned Manga lives in module_book_rows.lua.

local rows = require("desktop_modules/module_book_rows")
for _, mod in ipairs(rows.sub_modules or {}) do
    if mod.id == "pinned_manga" then
        return mod
    end
end

local RowRenderer = require("desktop_modules/mui_book_row")
local Manga       = require("desktop_modules/module_manga")
return RowRenderer.makeModule{
    id          = "pinned_manga",
    name        = "Pinned Manga",
    label       = "Pinned Manga",
    default_on  = true,
    is_book_mod = true,
    has_covers  = true,
    max_items   = 5,
    paged       = true,
    cache_key   = "_pinned_manga_fps",
    getFileList = Manga.getPinnedMangaList,
}
