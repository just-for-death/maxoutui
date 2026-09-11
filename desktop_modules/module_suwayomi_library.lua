-- module_suwayomi_library.lua — MaxOutUI
-- Suwayomi Library home module: displays the user's Suwayomi manga library on the home
-- screen using the standardized RowRenderer cover row architecture (same as Recent Books).

local _           = require("mui_i18n").translate
local RowRenderer = require("desktop_modules/mui_book_row")
local SwBridge    = require("desktop_modules/suwayomi_bridge")
local SUISettings = require("mui_store")
local UIManager   = require("ui/uimanager")

local MOD_ID = "suwayomi_library"
local CACHE_SETTING = "maxoutui_suwayomi_library_cache"

-- Shared cache for Suwayomi library manga fetched in background
local _library_cache      = nil
local _library_cache_time = 0
local _library_fetch_inflight = false

-- Restore saved cache on startup for instant rendering
pcall(function()
    local saved = SUISettings:readSetting(CACHE_SETTING)
    if type(saved) == "table" and #saved > 0 then
        _library_cache = saved
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

--- Sort manga list by unread_count descending, then alphabetically by title.
local function sortByUnread(manga_list)
    table.sort(manga_list, function(a, b)
        local ua = a.unread_count or 0
        local ub = b.unread_count or 0
        if ua ~= ub then
            return ua > ub
        end
        local ta = (a.title or ""):lower()
        local tb = (b.title or ""):lower()
        return ta < tb
    end)
    return manga_list
end

--- Prefetch uncached cover thumbnails in the background.
local function prefetchThumbnailsAsync(credentials, manga_list)
    local TC = getThumbnailCache()
    if not TC or not credentials or not manga_list then return end
    local sw = getSuwayomiPlugin()
    if not sw then return end

    for _, manga in ipairs(manga_list) do
        local thumb_url = manga.thumbnail_url
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

--- Fetch the library manga list asynchronously. Results are sorted by unread count and cached.
local function fetchLibraryAsync(callback)
    local now = os.time()
    if _library_cache and (now - _library_cache_time < 300) then
        if callback then callback(_library_cache) end
        return
    end
    if _library_fetch_inflight then
        if callback then callback(_library_cache or {}) end
        return
    end

    local sw = getSuwayomiPlugin()
    if not sw or not sw.getClient then
        if callback then callback(_library_cache or {}) end
        return
    end

    local NetworkRequestJob = package.loaded["suwayomi/network/request_job"] or require("suwayomi/network/request_job")
    local SuwayomiSettings  = getSuwayomiSettings()
    local credentials       = SuwayomiSettings and SuwayomiSettings:load()

    if not credentials or not credentials.server_url or credentials.server_url == "" then
        if callback then callback(_library_cache or {}) end
        return
    end

    _library_fetch_inflight = true
    NetworkRequestJob.start({
        owner       = sw,
        credentials = credentials,
        request     = { action = "fetch_library_manga_pages" },
        timeout_seconds = 30,
        on_finish = function(result)
            _library_fetch_inflight = false
            if result and result.ok and result.manga then
                local sorted = sortByUnread(result.manga)
                _library_cache      = sorted
                _library_cache_time = os.time()
                pcall(function() SUISettings:saveSetting(CACHE_SETTING, sorted) end)
                prefetchThumbnailsAsync(credentials, _library_cache)
                SwBridge.refreshHomescreenModule(MOD_ID)
                if callback then callback(_library_cache) end
            else
                if callback then callback(_library_cache or {}) end
            end
        end,
    })
end

local M = RowRenderer.makeModule{
    id          = MOD_ID,
    name        = _("Manga Library (Suwayomi)"),
    label       = _("Manga Library"),
    default_on  = false,
    is_book_mod = true,
    has_covers  = true,
    max_items   = 5,
    paged       = true,
    cache_key   = "_suwayomi_library_fps",

    getFileList = function(ctx)
        fetchLibraryAsync()
        if not _library_cache then
            local saved = SUISettings:readSetting(CACHE_SETTING)
            if type(saved) == "table" and #saved > 0 then
                _library_cache = saved
            end
        end
        local list = {}
        for _, manga in ipairs(_library_cache or {}) do
            if manga.id then
                local uri = "suwayomi://manga/" .. manga.id
                SwBridge.registerManga(manga)
                list[#list + 1] = uri
            end
        end
        return list
    end,

    labelForItem = function(bd)
        if bd.unread and bd.unread > 0 then
            return string.format(_("%d unread"), bd.unread)
        else
            return _("Up to date")
        end
    end,

    toggles = { progress = "off", text = "on", overlay = "off" },

    extra_menu_items_after = function(ctx_menu)
        local _lc = ctx_menu._
        return {
            {
                text           = _lc("Refresh Library"),
                keep_menu_open = true,
                callback       = function()
                    M.refresh(function()
                        ctx_menu.refresh()
                    end)
                end,
            },
            {
                text     = _lc("Open Manga Library…"),
                callback = function()
                    local sw = SwBridge.getSuwayomiPlugin()
                    if sw and sw.showLibrary then sw:showLibrary() end
                end,
            },
        }
    end,

    reset = function()
        _library_cache      = nil
        _library_cache_time = 0
        RowRenderer.reset()
    end,
}

--- Fetch if cache is empty/stale (respects TTL). Safe to call from Status build.
function M.ensureFetched(callback)
    fetchLibraryAsync(callback)
end

--- Clear the TTL cache and refetch library manga. Used by the library menu
--- and by module_suwayomi_status so Refresh actually hits the network.
function M.refresh(callback)
    _library_cache      = nil
    _library_cache_time = 0
    fetchLibraryAsync(callback)
end

--- Returns a snapshot of cached library stats for use by sibling modules
--- (e.g. module_suwayomi_status) via package.loaded. Returns nil when the
--- cache is empty so callers can distinguish "not fetched yet" from "zero".
function M.getCacheStats()
    if not _library_cache then return nil end
    local total_unread = 0
    for _, manga in ipairs(_library_cache) do
        total_unread = total_unread + (manga.unread_count or 0)
    end
    return {
        total_manga  = #_library_cache,
        total_unread = total_unread,
        cache_time   = _library_cache_time,
    }
end

return M
