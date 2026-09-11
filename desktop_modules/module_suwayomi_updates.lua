-- module_suwayomi_updates.lua — MaxOutUI
-- Suwayomi Updates home module: displays recently updated manga chapters from Suwayomi server
-- using the standardized RowRenderer cover row architecture (same as Recent Books).

local _           = require("mui_i18n").translate
local RowRenderer = require("desktop_modules/mui_book_row")
local SwBridge    = require("desktop_modules/suwayomi_bridge")
local SUISettings = require("mui_store")
local UIManager   = require("ui/uimanager")

local MOD_ID = "suwayomi_updates"
local CACHE_SETTING = "maxoutui_suwayomi_updates_cache"

-- Shared cache for Suwayomi updates entries fetched in background
local _updates_cache      = nil
local _updates_cache_time = 0
local _updates_fetch_inflight = false

-- Restore saved cache on startup for instant rendering
pcall(function()
    local saved = SUISettings:readSetting(CACHE_SETTING)
    if type(saved) == "table" and #saved > 0 then
        _updates_cache = saved
    end
end)

local function getSuwayomiPlugin()
    return SwBridge.getSuwayomiPlugin()
end

local function getThumbnailCache()
    local ok, tc = pcall(require, "suwayomi/ui/thumbnail_cache")
    return ok and tc or nil
end

local function getSuwayomiSettings()
    local ok, st = pcall(require, "suwayomi/settings")
    return ok and st or nil
end

--- Prefetches uncached cover thumbnails in background
local function prefetchThumbnailsAsync(credentials, entries)
    local TC = getThumbnailCache()
    if not TC or not credentials or not entries then return end
    local sw = getSuwayomiPlugin()
    if not sw then return end

    for _, entry in ipairs(entries) do
        local manga = entry.manga
        local thumb_url = manga and manga.thumbnail_url
        if thumb_url and thumb_url ~= "" then
            local cached = TC.find(credentials, thumb_url, { variant = "thumbnail" })
            if not cached then
                local started = SwBridge.startThumbJob(function(done)
                    local SubprocessJob   = package.loaded["suwayomi/subprocess/job"] or require("suwayomi/subprocess/job")
                    local ThumbnailWorker = package.loaded["suwayomi/ui/thumbnail_worker"] or require("suwayomi/ui/thumbnail_worker")
                    local FFIUtil         = require("ffi/util")

                    SubprocessJob.start({
                        active = {
                            request = { action = "download_thumbnail" },
                            result_path = SubprocessJob.buildResultPath("thumb_request"),
                        },
                        ffi_util    = FFIUtil,
                        ui_manager  = UIManager,
                        timeout_seconds = 15,
                        run = function(path)
                            ThumbnailWorker:run(credentials, thumb_url, path, { variant = "thumbnail" })
                        end,
                        on_finish = function()
                            done()
                            SwBridge.refreshHomescreenModule(MOD_ID, { debounce = 0.35 })
                        end,
                        on_timeout = function()
                            done()
                        end,
                    })
                end)
                if not started then break end
            end
        end
    end
end

--- Tries to fetch latest updates entries silently if suwayomiplus is available
local function fetchUpdatesEntriesAsync(callback)
    local now = os.time()
    if _updates_cache and (now - _updates_cache_time < 300) then
        if callback then callback(_updates_cache) end
        return
    end
    if _updates_fetch_inflight then
        if callback then callback(_updates_cache or {}) end
        return
    end

    local sw = getSuwayomiPlugin()
    if not sw or not sw.getClient then
        if callback then callback(_updates_cache or {}) end
        return
    end

    local NetworkRequestJob = package.loaded["suwayomi/network/request_job"] or require("suwayomi/network/request_job")
    local SuwayomiSettings = getSuwayomiSettings()
    local credentials = SuwayomiSettings and SuwayomiSettings:load()

    if not credentials or not credentials.server_url or credentials.server_url == "" then
        if callback then callback(_updates_cache or {}) end
        return
    end

    _updates_fetch_inflight = true
    NetworkRequestJob.start({
        owner = sw,
        credentials = credentials,
        request = { action = "fetch_updates", first = 25 },
        timeout_seconds = 15,
        on_finish = function(result)
            _updates_fetch_inflight = false
            if result and result.ok and result.entries then
                _updates_cache = result.entries
                _updates_cache_time = os.time()
                pcall(function() SUISettings:saveSetting(CACHE_SETTING, result.entries) end)
                prefetchThumbnailsAsync(credentials, _updates_cache)
                SwBridge.refreshHomescreenModule(MOD_ID)
                if callback then callback(_updates_cache) end
            else
                if callback then callback(_updates_cache or {}) end
            end
        end,
    })
end

local M = RowRenderer.makeModule{
    id          = MOD_ID,
    name        = _("Manga Updates (Suwayomi)"),
    label       = _("New Chapters"),
    default_on  = false,
    is_book_mod = true,
    has_covers  = true,
    max_items   = 5,
    paged       = true,
    cache_key   = "_suwayomi_updates_fps",

    getFileList = function(ctx)
        fetchUpdatesEntriesAsync()
        if not _updates_cache then
            local saved = SUISettings:readSetting(CACHE_SETTING)
            if type(saved) == "table" and #saved > 0 then
                _updates_cache = saved
            end
        end
        local list = {}
        local seen = {}
        for _, entry in ipairs(_updates_cache or {}) do
            local manga = entry.manga
            if manga and manga.id and not seen[manga.id] then
                seen[manga.id] = true
                local uri = "suwayomi://manga/" .. manga.id
                local ch_name = entry.chapter and (entry.chapter.name or (entry.chapter.chapter_number and ("Ch. " .. entry.chapter.chapter_number)))
                SwBridge.registerManga(manga, { chapter_name = ch_name })
                list[#list + 1] = uri
            end
        end
        return list
    end,

    labelForItem = function(bd)
        local ch = bd.chapter_name
        if ch and ch ~= "" then
            ch = ch:gsub("^Chapter%s+", "Ch. ")
            ch = ch:gsub("^Volume%s+", "Vol. ")
            return ch
        end
        return (bd.title and bd.title ~= "" and bd.title) or _("Updated")
    end,

    toggles = { progress = "off", text = "on", overlay = "off" },

    extra_menu_items_after = function(ctx_menu)
        local _lc = ctx_menu._
        return {
            {
                text           = _lc("Refresh Updates"),
                keep_menu_open = true,
                callback       = function()
                    M.refresh(function()
                        ctx_menu.refresh()
                    end)
                end,
            },
            {
                text     = _lc("Open Updates Screen…"),
                callback = function()
                    local sw = SwBridge.getSuwayomiPlugin()
                    if sw and sw.showUpdates then sw:showUpdates() end
                end,
            },
        }
    end,

    reset = function()
        _updates_cache      = nil
        _updates_cache_time = 0
        RowRenderer.reset()
    end,
}

function M.refresh(callback)
    _updates_cache      = nil
    _updates_cache_time = 0
    fetchUpdatesEntriesAsync(callback)
end

return M
