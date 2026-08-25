-- module_manga.lua — Simple UI
-- Pinned Manga data/API layer.  Mirrors module_tbr.lua in structure.
--
-- Stores user-pinned manga in a KOReader collection named "Pinned Manga".
-- The corresponding cover row module (pinned_manga) lives in module_book_rows.lua,
-- which requires this file for list/add/remove/arrange helpers.
--
-- Public API (consumed by module_book_rows.lua, main.lua):
--   M.MANGA_COLL_NAME                         → string
--   M.getPinnedMangaList()                     → { fp, ... }
--   M.getPinnedMangaCount()                    → number
--   M.isPinnedManga(filepath)                  → bool
--   M.addPinnedManga(filepath)                 → bool
--   M.removePinnedManga(filepath)
--   M.genPinnedMangaButton(file, close_cb)     → button table
--   M.arrangeMenuItems(ctx_menu)               → { item, ... }

local lfs    = require("libs/libkoreader-lfs")
local _      = require("sui_i18n").translate
local logger = require("logger")

local SUISettings = require("sui_store")

local MANGA_MAX       = 999
local MANGA_SETTING   = "simpleui_pinned_manga_list"
local MANGA_COLL_NAME = "Pinned Manga"

local function getRC()
    local ok, rc = pcall(require, "readcollection")
    if ok and rc then
        if not rc.coll then
            pcall(function() rc:init() end)
        end
        return rc
    end
    return nil
end

local function _migrate()
    local RC = getRC()
    if not RC then return end
    if not (RC.coll and RC.coll[MANGA_COLL_NAME]) then
        RC:addCollection(MANGA_COLL_NAME)
    end
    if RC.coll and RC.coll[MANGA_COLL_NAME] and next(RC.coll[MANGA_COLL_NAME]) then return end
    local raw = SUISettings:readSetting(MANGA_SETTING)
    if type(raw) ~= "table" or #raw == 0 then return end
    local added = 0
    for _, fp in ipairs(raw) do
        if type(fp) == "string" and (fp:match("^suwayomi://") or lfs.attributes(fp, "mode") == "file") then
            RC:addItem(fp, MANGA_COLL_NAME)
            added = added + 1
        end
    end
    if added > 0 then
        RC:write({ [MANGA_COLL_NAME] = true })
        logger.dbg("simpleui: module_manga: migrated", added, "entries to ReadCollection")
    end
end

pcall(_migrate)

local function getPinnedMangaList()
    local RC = getRC()
    local list = {}
    local seen = {}
    if RC and RC.coll and RC.coll[MANGA_COLL_NAME] then
        local items = {}
        for _, item in pairs(RC.coll[MANGA_COLL_NAME]) do
            if type(item) == "table" and type(item.file) == "string" then
                if item.file:match("^suwayomi://") or (lfs.attributes(item.file, "mode") == "file") then
                    items[#items + 1] = item
                end
            end
        end
        table.sort(items, function(a, b) return (a.order or 0) < (b.order or 0) end)
        for _, item in ipairs(items) do
            list[#list + 1] = item.file
            seen[item.file] = true
        end
    end
    local raw = SUISettings:readSetting(MANGA_SETTING)
    if type(raw) == "table" then
        for _, fp in ipairs(raw) do
            if type(fp) == "string" and not seen[fp] and (fp:match("^suwayomi://") or (lfs.attributes(fp, "mode") == "file")) then
                list[#list + 1] = fp
                seen[fp] = true
            end
        end
    end
    return list
end

local function _syncSettings(list)
    SUISettings:saveSetting(MANGA_SETTING, list)
end

local function getPinnedMangaCount()
    return #getPinnedMangaList()
end

local function isPinnedManga(filepath)
    if not filepath then return false end
    for _, fp in ipairs(getPinnedMangaList()) do
        if fp == filepath then return true end
    end
    return false
end

local TITLE_SETTING = "simpleui_pinned_manga_titles"
local COVER_SETTING = "simpleui_pinned_manga_covers"

local function normalizeCoverPath(path)
    if type(path) == "string" and path ~= "" then
        local real_path = path
        if real_path:sub(1, 2) == "./" then
            local ok_ds, DataStorage = pcall(require, "datastorage")
            if ok_ds and DataStorage then
                local settings_dir = DataStorage:getSettingsDir()
                local data_dir = DataStorage:getDataDir()
                if real_path:sub(1, 11) == "./settings/" then
                    real_path = settings_dir .. "/" .. real_path:sub(12)
                else
                    real_path = data_dir .. "/" .. real_path:sub(3)
                end
            end
        end
        if lfs.attributes(real_path, "mode") == "file" then
            return real_path
        end
    end
    return nil
end

local function getPinnedMangaCover(fp)
    if not fp then return nil end
    local covers = SUISettings:readSetting(COVER_SETTING)
    if type(covers) == "table" and covers[fp] then
        local norm = normalizeCoverPath(covers[fp])
        if norm then return norm end
    end
    local manga_id = tostring(fp):match("^suwayomi://manga/(%d+)$")
    if manga_id then
        local ok, SuwayomiSettings = pcall(require, "suwayomi/settings")
        if ok and SuwayomiSettings then
            local creds = SuwayomiSettings:load()
            local ok_tc, tc = pcall(require, "suwayomi/ui/thumbnail_cache")
            if ok_tc and tc then
                local variants = {
                    { variant = "manga_cover", width = 64, height = 96 },
                    { variant = "poster", width = 240, height = 360 },
                    { variant = "thumbnail", width = 64, height = 96 },
                    { variant = "poster", width = 160, height = 240 },
                    { variant = "poster", width = 320, height = 480 },
                    {},
                }
                local pinned = SuwayomiSettings.loadPinnedManga and SuwayomiSettings:loadPinnedManga() or {}
                for _, pm in ipairs(pinned) do
                    if tostring(pm.id) == manga_id and pm.thumbnail_url then
                        for _, opts in ipairs(variants) do
                            local path = tc.find(creds, pm.thumbnail_url, opts)
                            local norm = normalizeCoverPath(path)
                            if norm then
                                if type(covers) ~= "table" then covers = {} end
                                covers[fp] = norm
                                SUISettings:saveSetting(COVER_SETTING, covers)
                                return norm
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function _getBookTitle(fp)
    local title = fp:match("([^/]+)%.[^%.]+$") or fp
    pcall(function()
        local DS = require("docsettings")
        local ok2, ds = pcall(DS.open, DS, fp)
        if ok2 and ds then
            local rp = ds:readSetting("doc_props") or {}
            if rp.title and rp.title ~= "" then title = rp.title end
            pcall(function() ds:close() end)
        end
    end)
    if #title > 48 then title = title:sub(1, 45) .. "…" end
    return title
end

local function getPinnedMangaTitle(fp)
    local titles = SUISettings:readSetting(TITLE_SETTING)
    if type(titles) == "table" and titles[fp] and titles[fp] ~= "" then
        return titles[fp]
    end
    local RC = getRC()
    if RC and RC.coll and RC.coll[MANGA_COLL_NAME] and RC.coll[MANGA_COLL_NAME][fp] then
        local text = RC.coll[MANGA_COLL_NAME][fp].text
        if text and text ~= "" then return text end
    end
    return _getBookTitle(fp)
end

local function addPinnedManga(filepath, custom_title, cover_path)
    if isPinnedManga(filepath) then return true end
    local current = getPinnedMangaList()
    current[#current + 1] = filepath
    _syncSettings(current)

    if custom_title and custom_title ~= "" then
        local titles = SUISettings:readSetting(TITLE_SETTING)
        if type(titles) ~= "table" then titles = {} end
        titles[filepath] = custom_title
        SUISettings:saveSetting(TITLE_SETTING, titles)
    end

    if cover_path and cover_path ~= "" then
        local covers = SUISettings:readSetting(COVER_SETTING)
        if type(covers) ~= "table" then covers = {} end
        covers[filepath] = cover_path
        SUISettings:saveSetting(COVER_SETTING, covers)
    end

    local RC = getRC()
    if RC then
        if not (RC.coll and RC.coll[MANGA_COLL_NAME]) then
            RC:addCollection(MANGA_COLL_NAME)
        end
        local is_virtual = tostring(filepath):match("^suwayomi://")
        local ffiUtil = require("ffi/util")
        local lfs2    = require("libs/libkoreader-lfs")
        local real    = is_virtual and filepath or (ffiUtil.realpath(filepath) or filepath)
        if is_virtual or (real and lfs2.attributes(real, "mode") == "file") then
            local max_order = 0
            for _, item in pairs(RC.coll[MANGA_COLL_NAME]) do
                if (item.order or 0) > max_order then max_order = item.order end
            end
            local attr = is_virtual and { mode = "file", size = 0 } or lfs2.attributes(real)
            local display_title = custom_title or real:gsub(".*/", "")
            RC.coll[MANGA_COLL_NAME][real] = {
                file  = real,
                text  = display_title,
                order = max_order + 1,
                attr  = attr,
            }
            pcall(function() RC:write({ [MANGA_COLL_NAME] = true }) end)
        end
    end
    return true
end

local function removePinnedManga(filepath)
    local current = getPinnedMangaList()
    local updated = {}
    for _, fp in ipairs(current) do
        if fp ~= filepath then updated[#updated + 1] = fp end
    end
    _syncSettings(updated)

    local titles = SUISettings:readSetting(TITLE_SETTING)
    if type(titles) == "table" and titles[filepath] then
        titles[filepath] = nil
        SUISettings:saveSetting(TITLE_SETTING, titles)
    end

    local covers = SUISettings:readSetting(COVER_SETTING)
    if type(covers) == "table" and covers[filepath] then
        covers[filepath] = nil
        SUISettings:saveSetting(COVER_SETTING, covers)
    end

    local RC = getRC()
    if RC and RC.coll and RC.coll[MANGA_COLL_NAME] then
        local coll = RC.coll[MANGA_COLL_NAME]
        coll[filepath] = nil
        local ok_fu, ffiUtil = pcall(require, "ffi/util")
        local real = ok_fu and ffiUtil.realpath(filepath)
        if real then coll[real] = nil end
        pcall(function() RC:write({ [MANGA_COLL_NAME] = true }) end)
    end
end


local function arrangeMenuItems(ctx_menu)
    local _lc        = ctx_menu._
    local refresh     = ctx_menu.refresh
    local SortWidget  = ctx_menu.SortWidget
    local _UIManager  = ctx_menu.UIManager
    local InfoMessage = ctx_menu.InfoMessage

    return {
        {
            text = _lc("Arrange"),
            sub_item_table_func = function()
                local sub_items = {}

                sub_items[#sub_items + 1] = {
                    text           = _lc("Arrange Pinned Manga List"),
                    enabled_func   = function() return getPinnedMangaCount() > 1 end,
                    keep_menu_open = true,
                    callback = function()
                        local list = getPinnedMangaList()
                        if #list < 2 then
                            _UIManager:show(InfoMessage:new{
                                text = _lc("Add at least 2 items to arrange."), timeout = 2 })
                            return
                        end
                        local sort_items = {}
                        for _, fp in ipairs(list) do
                            sort_items[#sort_items + 1] = {
                                text      = getPinnedMangaTitle(fp),
                                filepath  = fp,
                                mandatory = "",
                            }
                        end
                        local function on_save()
                            local new_list = {}
                            for _, item in ipairs(sort_items) do
                                if item.filepath then
                                    new_list[#new_list + 1] = item.filepath
                                end
                            end
                            local RC2 = getRC()
                            if RC2 and RC2.coll[MANGA_COLL_NAME] then
                                local ordered = {}
                                for _, fp in ipairs(new_list) do
                                    local entry = RC2.coll[MANGA_COLL_NAME][fp]
                                    if entry then ordered[#ordered + 1] = entry end
                                end
                                RC2:updateCollectionOrder(MANGA_COLL_NAME, ordered)
                                RC2:write({ [MANGA_COLL_NAME] = true })
                            end
                            _syncSettings(new_list)
                            refresh()
                        end
                        _UIManager:show(SortWidget:new{
                            title             = _lc("Arrange Pinned Manga List"),
                            item_table        = sort_items,
                            covers_fullscreen = true,
                            callback          = on_save,
                        })
                    end,
                }

                sub_items[#sub_items + 1] = {
                    text = _lc("Pinned Manga"), enabled = false, separator = true
                }

                local list = getPinnedMangaList()
                if #list == 0 then
                    sub_items[#sub_items + 1] = {
                        text = _lc("No manga pinned yet."), enabled = false
                    }
                else
                    for _, fp in ipairs(list) do
                        local _fp    = fp
                        local _title = getPinnedMangaTitle(fp)
                        sub_items[#sub_items + 1] = {
                            text           = _title,
                            checked_func   = function() return isPinnedManga(_fp) end,
                            keep_menu_open = true,
                            callback       = function()
                                removePinnedManga(_fp)
                                refresh()
                            end,
                        }
                    end
                end

                return sub_items
            end,
            sui_build = ctx_menu.is_sui and function(ctx, _item)
                local SUIWindow = require("sui_window")
                return SUIWindow.ListRow{
                    title        = _lc("Arrange"),
                    subtitle     = function()
                        local list = getPinnedMangaList()
                        if #list == 0 then return _lc("No manga pinned yet.") end
                        local names = {}
                        for _, fp in ipairs(list) do
                            names[#names + 1] = getPinnedMangaTitle(fp)
                        end
                        return table.concat(names, "  ·  ")
                    end,
                    inner_w      = ctx.inner_w,
                    show_chevron = true,
                    on_tap       = function()
                        local list = getPinnedMangaList()
                        local sort_items = {}
                        for _, fp in ipairs(list) do
                            sort_items[#sort_items + 1] = {
                                text      = getPinnedMangaTitle(fp),
                                orig_item = fp,
                            }
                        end
                        ctx.push("nested_menu", {
                            title = _lc("Arrange"),
                            items_func = function()
                                return {
                                    {
                                        text = "Items List",
                                        sui_build = function(ctx2)
                                            local SUIWindow2 = require("sui_window")
                                            local function save_order(items_to_save)
                                                local new_list = {}
                                                for _, it in ipairs(items_to_save) do
                                                    new_list[#new_list + 1] = it.orig_item
                                                end
                                                local RC2 = getRC()
                                                if RC2 and RC2.coll[MANGA_COLL_NAME] then
                                                    local ordered = {}
                                                    for _, fp in ipairs(new_list) do
                                                        local entry = RC2.coll[MANGA_COLL_NAME][fp]
                                                        if entry then ordered[#ordered + 1] = entry end
                                                    end
                                                    RC2:updateCollectionOrder(MANGA_COLL_NAME, ordered)
                                                    RC2:write({ [MANGA_COLL_NAME] = true })
                                                end
                                                _syncSettings(new_list)
                                            end
                                            local cards = {}
                                            for i, item in ipairs(sort_items) do
                                                local _i  = i
                                                local _fp = item.orig_item
                                                cards[#cards + 1] = SUIWindow2.ArrangeCard{
                                                    inner_w      = ctx2.inner_w,
                                                    title        = item.text,
                                                    on_delete    = function()
                                                        table.remove(sort_items, _i)
                                                        removePinnedManga(_fp)
                                                        ctx_menu.refresh()
                                                        ctx2.repaint()
                                                    end,
                                                    on_move_up   = (_i > 1) and function()
                                                        sort_items[_i], sort_items[_i-1] = sort_items[_i-1], sort_items[_i]
                                                        save_order(sort_items)
                                                        ctx_menu.refresh()
                                                        ctx2.repaint()
                                                    end or nil,
                                                    on_move_down = (_i < #sort_items) and function()
                                                        sort_items[_i], sort_items[_i+1] = sort_items[_i+1], sort_items[_i]
                                                        save_order(sort_items)
                                                        ctx_menu.refresh()
                                                        ctx2.repaint()
                                                    end or nil,
                                                }
                                            end
                                            if #cards == 0 then
                                                cards[#cards + 1] = SUIWindow2.ListRow{
                                                    title   = _lc("No manga pinned yet."),
                                                    inner_w = ctx2.inner_w,
                                                }
                                            end
                                            return cards
                                        end
                                    }
                                }
                            end
                        })
                    end
                }
            end or nil,
        },
    }
end

local M = {}

M.MANGA_COLL_NAME     = MANGA_COLL_NAME
M.MANGA_MAX           = MANGA_MAX
M.getPinnedMangaList  = getPinnedMangaList
M.getPinnedMangaTitle = getPinnedMangaTitle
M.getPinnedMangaCover = getPinnedMangaCover
M.getPinnedMangaCount = getPinnedMangaCount
M.isPinnedManga       = isPinnedManga
M.addPinnedManga      = addPinnedManga
M.removePinnedManga   = removePinnedManga
M.arrangeMenuItems    = arrangeMenuItems

function M.getDisplayName()
    return _("Pinned Manga")
end

function M.genPinnedMangaButton(file, close_cb)
    local in_pinned = isPinnedManga(file)
    local count     = getPinnedMangaCount()
    local indicator = string.format("(%d)", count)
    return {
        text     = (in_pinned and _("Unpin Manga") or _("Pin Manga"))
                   .. "  " .. indicator,
        enabled  = true,
        callback = function()
            if in_pinned then removePinnedManga(file) else addPinnedManga(file) end
            if close_cb then close_cb() end
        end,
    }
end

return M
