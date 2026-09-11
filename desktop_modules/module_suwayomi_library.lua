-- module_suwayomi_library.lua — Simple UI
-- Suwayomi Library home module: displays the user's Suwayomi manga library on the home
-- screen, sorted by unread count. Covers are loaded from Suwayomi's local ThumbnailCache
-- if cached, or a placeholder if not. Tapping an item with unread chapters resumes reading
-- via suwayomiplus; otherwise opens the manga actions/chapters screen.

local Device      = require("device")
local Screen      = Device.screen
local Blitbuffer  = require("ffi/blitbuffer")
local Font        = require("ui/font")
local Geom        = require("ui/geometry")
local UIManager   = require("ui/uimanager")

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local ImageWidget     = require("ui/widget/imagewidget")

local _ = require("mui_i18n").translate
local Config      = require("mui_config")
local UI          = require("mui_core")
local SUISettings = require("mui_store")
local SUIStyle    = require("mui_style")
local RowRenderer = require("desktop_modules/mui_book_row")
local SwBridge    = require("desktop_modules/suwayomi_bridge")

local PAD    = UI.PAD
local MOD_ID = "suwayomi_library"

local M = {}
M.id          = MOD_ID
M.name        = _("Manga Library (Suwayomi)")
M.label       = _("Manga Library")
M.default_on  = false
M.enabled_key = MOD_ID .. "_enabled"
M.has_covers  = true
M.is_book_mod = true

-- Shared cache for Suwayomi library manga fetched in background
local _library_cache      = nil
local _library_cache_time = 0

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
--- manga_list is a flat array of manga objects (each with .thumbnail_url).
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
                pcall(function()
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
                            local HS = package.loaded["mui_homescreen"]
                            local hs_inst = HS and HS._instance
                            if hs_inst then
                                pcall(function()
                                    if hs_inst._refreshImmediate then
                                        hs_inst:_refreshImmediate(true)
                                    else
                                        UIManager:setDirty(hs_inst, "ui")
                                    end
                                end)
                            end
                        end,
                    })
                end)
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

    NetworkRequestJob.start({
        owner       = sw,
        credentials = credentials,
        request     = { action = "fetch_library_manga_pages" },
        timeout_seconds = 30,
        on_finish = function(result)
            if result and result.ok and result.manga then
                local sorted = sortByUnread(result.manga)
                _library_cache      = sorted
                _library_cache_time = os.time()
                prefetchThumbnailsAsync(credentials, _library_cache)
                local HS = package.loaded["mui_homescreen"]
                local hs_inst = HS and HS._instance
                if hs_inst then
                    pcall(function()
                        if hs_inst._refreshImmediate then
                            hs_inst:_refreshImmediate(true)
                        else
                            UIManager:setDirty(hs_inst, "ui")
                        end
                    end)
                end
                if callback then callback(_library_cache) end
            else
                if callback then callback(_library_cache or {}) end
            end
        end,
    })
end

function M.build(w, ctx)
    local pfx = ctx and ctx.pfx or ""
    local scale       = Config.getModuleScale(MOD_ID, pfx)
    local thumb_scale = Config.getThumbScale(MOD_ID, pfx)
    local lbl_scale   = Config.getItemLabelScale(MOD_ID, pfx)

    local SH = nil
    pcall(function() SH = require("desktop_modules/module_books_shared") end)
    local D = SH and SH.getDims(scale, thumb_scale) or { RECENT_W = 120, RECENT_H = 170 }

    local max_items  = 5
    local inner_w    = w - PAD * 2
    local autofit_cw = math.max(1, math.floor((inner_w - (max_items - 1) * PAD) / max_items))
    local cs         = scale * thumb_scale
    local cw         = (cs == 1.0) and autofit_cw or math.max(1, math.floor(autofit_cw * cs))
    local rh         = math.max(1, math.floor(cw * (D.RECENT_H / D.RECENT_W)))

    -- Trigger async fetch if needed
    fetchLibraryAsync(function(_manga_list)
        -- UI refresh is handled inside fetchLibraryAsync on_finish
    end)

    local manga_list = _library_cache or {}
    local item_group = HorizontalGroup:new{}

    local sw          = getSuwayomiPlugin()
    local TC          = getThumbnailCache()
    local credentials = getSuwayomiSettings() and getSuwayomiSettings():load()

    local count = 0
    for i, manga in ipairs(manga_list) do
        if count >= max_items then break end
        local title     = manga.title or "Manga"
        local thumb_url = manga.thumbnail_url
        local unread    = manga.unread_count or 0

        count = count + 1
        if count > 1 then
            item_group[#item_group + 1] = HorizontalSpan:new{ width = PAD }
        end

        local cover_w = cw
        local cover_h = rh
        local cover_widget

        local cached_path  = TC and credentials and TC.find(credentials, thumb_url, { variant = "thumbnail" })
        local decoded_bmp  = cached_path and TC.loadDecoded(cached_path)

        if decoded_bmp then
            cover_widget = ImageWidget:new{
                image        = decoded_bmp,
                width        = cover_w,
                height       = cover_h,
                scale_factor = 0,
            }
        else
            -- Placeholder box with title
            cover_widget = FrameContainer:new{
                width      = cover_w,
                height     = cover_h,
                bordersize = 1,
                color      = Blitbuffer.gray(0.6),
                background = Blitbuffer.gray(0.9),
                padding    = 4,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_w - 8, h = cover_h - 8 },
                    TextBoxWidget:new{
                        text      = title,
                        face      = Font:getFace(SUIStyle.FACE_REGULAR, math.max(10, math.floor(12 * scale))),
                        width     = cover_w - 8,
                        alignment = "center",
                    }
                }
            }
        end

        -- Subtitle: unread count or up-to-date indicator
        local sub_txt
        if unread > 0 then
            sub_txt = unread .. " " .. _("unread")
        else
            sub_txt = _("Up to date")
        end
        local sub_widget = TextWidget:new{
            text    = sub_txt,
            face    = Font:getFace(SUIStyle.FACE_REGULAR, math.max(9, math.floor(11 * scale * lbl_scale))),
            fgcolor = Blitbuffer.gray(0.3),
        }

        local cell = VerticalGroup:new{
            align = "center",
            cover_widget,
            VerticalSpan:new{ width = Screen:scaleBySize(3) },
            sub_widget,
        }

        -- Capture loop variable for the closure
        local _manga = manga
        local cell_h = rh + Screen:scaleBySize(20)
        item_group[#item_group + 1] = SwBridge.makeTappable(cell, cw, cell_h, function()
            local sw_inst = SwBridge.requireSuwayomi()
            if not sw_inst then return end
            if (_manga.unread_count or 0) > 0 and sw_inst.resumeMangaStream then
                sw_inst:resumeMangaStream(_manga)
            elseif sw_inst.showMangaActions then
                sw_inst:showMangaActions(_manga)
            elseif sw_inst.showChaptersForManga then
                sw_inst:showChaptersForManga(_manga)
            end
        end)
    end

    if count == 0 then
        -- Empty state: tap opens full library
        local empty = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = rh },
            TextWidget:new{
                text    = _("No manga in your Suwayomi library."),
                face    = Font:getFace(SUIStyle.FACE_ITALIC, math.max(12, math.floor(14 * scale))),
                fgcolor = Blitbuffer.gray(0.5),
            }
        }
        item_group[#item_group + 1] = SwBridge.makeTappable(empty, inner_w, rh, function()
            local sw_inst = SwBridge.requireSuwayomi()
            if sw_inst and sw_inst.showLibrary then
                sw_inst:showLibrary()
            end
        end)
    end

    local content    = item_group
    local show_frame = RowRenderer and RowRenderer.showFrame and RowRenderer.showFrame(pfx, MOD_ID)
    local solid_bg   = RowRenderer and RowRenderer.solidBg and RowRenderer.solidBg(pfx, MOD_ID)
    local has_box    = show_frame or solid_bg
    local border_sz  = show_frame and SUIStyle.BORDER_SZ or 0
    local radius     = has_box and math.floor(Screen:scaleBySize(12) * scale) or 0
    local border_color = Blitbuffer.gray(0.72)

    return FrameContainer:new{
        bordersize     = border_sz,
        radius         = radius,
        color          = border_color,
        background     = solid_bg and Blitbuffer.COLOR_WHITE or nil,
        padding        = PAD,
        padding_top    = has_box and PAD or 0,
        padding_bottom = has_box and PAD or 0,
        content,
    }
end

function M.getHeight(_ctx)
    local pfx = _ctx and _ctx.pfx or ""
    local scale       = Config.getModuleScale(MOD_ID, pfx)
    local thumb_scale = Config.getThumbScale(MOD_ID, pfx)
    local SH = nil
    pcall(function() SH = require("desktop_modules/module_books_shared") end)
    local D = SH and SH.getDims(scale, thumb_scale) or { RECENT_W = 120, RECENT_H = 170 }

    local max_items  = 5
    local w          = (_ctx and (_ctx.col_w or _ctx.inner_w)) or (Screen:getWidth() - UI.SIDE_PAD * 2)
    local inner_w    = w - PAD * 2
    local autofit_cw = math.max(1, math.floor((inner_w - (max_items - 1) * PAD) / max_items))
    local cs         = scale * thumb_scale
    local cw         = (cs == 1.0) and autofit_cw or math.max(1, math.floor(autofit_cw * cs))
    local rh         = math.max(1, math.floor(cw * (D.RECENT_H / D.RECENT_W)))

    local h = rh + Screen:scaleBySize(20)
    if RowRenderer and (RowRenderer.showFrame(pfx, MOD_ID) or RowRenderer.solidBg(pfx, MOD_ID)) then
        h = h + PAD * 2
    end
    return Config.getScaledLabelH() + h
end

function M.updateCovers(_widget, _ctx)
    return true
end

function M.getMenuItems(ctx_menu)
    local _lc    = ctx_menu._
    local refresh = ctx_menu.refresh
    local pfx    = ctx_menu.pfx
    local items  = {}

    items[#items + 1] = {
        text           = _lc("Refresh Library"),
        keep_menu_open = true,
        callback       = function()
            _library_cache      = nil
            _library_cache_time = 0
            fetchLibraryAsync(function()
                refresh()
            end)
        end,
    }

    items[#items + 1] = Config.makeScaleItem{
        text_func    = function() return _lc("Scale") end,
        enabled_func = function() return not Config.isScaleLinked() end,
        title        = _lc("Scale"),
        info         = _lc("Scale for this module.\n100% is the default size."),
        get          = function() return Config.getModuleScalePct(MOD_ID, pfx) end,
        set          = function(v) Config.setModuleScale(v, MOD_ID, pfx) end,
        refresh      = refresh,
    }
    items[#items + 1] = Config.makeScaleItem{
        text_func = function() return _lc("Cover Size") end,
        separator = true,
        title     = _lc("Cover Size"),
        info      = _lc("Scale for the cover thumbnails.\n100% is the default size."),
        get       = function() return Config.getThumbScalePct(MOD_ID, pfx) end,
        set       = function(v) Config.setThumbScale(v, MOD_ID, pfx) end,
        refresh   = refresh,
    }

    items[#items + 1] = Config.makeLabelToggleItem(MOD_ID, M.label, refresh, _lc)

    return items
end

function M.reset()
    _library_cache      = nil
    _library_cache_time = 0
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
