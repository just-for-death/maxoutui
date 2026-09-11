-- module_suwayomi_updates.lua — Simple UI
-- Suwayomi Updates home module: displays recently updated manga chapters from Suwayomi server.
-- Covers are loaded from Suwayomi's local ThumbnailCache if cached, or placeholder if not.
-- Tapping any item or the module header opens Suwayomi Updates screen via suwayomiplus plugin.

local Device      = require("device")
local Screen      = Device.screen
local Blitbuffer  = require("ffi/blitbuffer")
local Font        = require("ui/font")
local Geom        = require("ui/geometry")
local GestureRange= require("ui/gesturerange")
local UIManager   = require("ui/uimanager")

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local ImageWidget     = require("ui/widget/imagewidget")

local _ = require("sui_i18n").translate
local Config      = require("sui_config")
local UI          = require("sui_core")
local SUISettings = require("sui_store")
local SUIStyle    = require("sui_style")
local RowRenderer = require("desktop_modules/sui_book_row")

local PAD     = UI.PAD
local MOD_ID  = "suwayomi_updates"

local M = {}
M.id          = MOD_ID
M.name        = _("Manga Updates (Suwayomi)")
M.label       = _("New Chapters")
M.default_on  = false
M.enabled_key = MOD_ID .. "_enabled"
M.has_covers  = true
M.is_book_mod = true

-- Shared cache for Suwayomi updates entries fetched in background
local _updates_cache = nil
local _updates_cache_time = 0

local function getSuwayomiPlugin()
    for key, m in pairs(package.loaded) do
        if type(key) == "string" and key:find("suwayomiplus", 1, true) then
            local inst = type(m) == "table" and (m.instance or m)
            if inst then return inst end
        end
    end
    for path_entry in (package.path or ""):gmatch("[^;]+") do
        local plugin_root = path_entry:match("^(.*suwayomiplus%.koplugin)/")
        if plugin_root then
            local mainfile = plugin_root .. "/main.lua"
            local ok, m = pcall(dofile, mainfile)
            if ok and m then
                local inst = type(m) == "table" and (m.instance or m)
                if inst then return inst end
            end
        end
    end
    local FM = package.loaded["apps/filemanager/filemanager"]
    local fm = FM and FM.instance
    if fm and fm.suwayomiplus then return fm.suwayomiplus end
    local RUI = package.loaded["apps/reader/readerui"]
    local rui = RUI and RUI.instance
    if rui and rui.suwayomiplus then return rui.suwayomiplus end
    return nil
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
                pcall(function()
                    local SubprocessJob   = package.loaded["suwayomi/subprocess/job"] or require("suwayomi/subprocess/job")
                    local ThumbnailWorker = package.loaded["suwayomi/ui/thumbnail_worker"] or require("suwayomi/ui/thumbnail_worker")
                    local FFIUtil         = require("ffi/util")

                    SubprocessJob.start({
                        active = {
                            request = { action = "download_thumbnail" },
                            result_path = SubprocessJob.buildResultPath("thumb_request"),
                        },
                        ffi_util = FFIUtil,
                        ui_manager = UIManager,
                        timeout_seconds = 15,
                        run = function(path)
                            ThumbnailWorker:run(credentials, thumb_url, path, { variant = "thumbnail" })
                        end,
                        on_finish = function()
                            local HS = package.loaded["sui_homescreen"]
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

--- Tries to fetch latest updates entries silently if suwayomiplus is available
local function fetchUpdatesEntriesAsync(callback)
    local now = os.time()
    if _updates_cache and (now - _updates_cache_time < 300) then
        if callback then callback(_updates_cache) end
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

    NetworkRequestJob.start({
        owner = sw,
        credentials = credentials,
        request = { action = "fetch_updates", first = 15 },
        timeout_seconds = 10,
        on_finish = function(result)
            if result and result.ok and result.entries then
                _updates_cache = result.entries
                _updates_cache_time = os.time()
                prefetchThumbnailsAsync(credentials, _updates_cache)
                local HS = package.loaded["sui_homescreen"]
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
                if callback then callback(_updates_cache) end
            else
                if callback then callback(_updates_cache or {}) end
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

    local max_items = 5
    local inner_w   = w - PAD * 2
    local autofit_cw = math.max(1, math.floor((inner_w - (max_items - 1) * PAD) / max_items))
    local cs = scale * thumb_scale
    local cw = (cs == 1.0) and autofit_cw or math.max(1, math.floor(autofit_cw * cs))
    local rh = math.max(1, math.floor(cw * (D.RECENT_H / D.RECENT_W)))

    -- Trigger async fetch if needed
    fetchUpdatesEntriesAsync(function(entries)
        if entries and #entries > 0 and ctx and ctx.hs and ctx.hs._refreshImmediate then
            -- Trigger UI refresh if new data arrived
        end
    end)

    local entries = _updates_cache or {}
    local item_group = HorizontalGroup:new{}

    local sw = getSuwayomiPlugin()
    local TC = getThumbnailCache()
    local credentials = getSuwayomiSettings() and getSuwayomiSettings():load()

    local count = 0
    for i, entry in ipairs(entries) do
        if count >= max_items then break end
        local manga   = entry.manga or {}
        local chapter = entry.chapter or {}
        local title   = manga.title or "Manga"
        local thumb_url = manga.thumbnail_url

        count = count + 1
        if count > 1 then
            item_group[#item_group + 1] = HorizontalSpan:new{ width = PAD }
        end

        local cover_w = cw
        local cover_h = rh
        local cover_widget = nil

        local cached_path = TC and credentials and TC.find(credentials, thumb_url, { variant = "thumbnail" })
        local decoded_bmp = cached_path and TC.loadDecoded(cached_path)

        if decoded_bmp then
            cover_widget = ImageWidget:new{
                image  = decoded_bmp,
                width  = cover_w,
                height = cover_h,
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
                        text  = title,
                        face  = Font:getFace(SUIStyle.FACE_REGULAR, math.max(10, math.floor(12 * scale))),
                        width = cover_w - 8,
                        alignment = "center",
                    }
                }
            }
        end

        -- Subtitle text: show the new chapter name/number from the update
        local sub_txt = chapter.name or (chapter.chapter_number and ("Ch. " .. chapter.chapter_number)) or ""
        local sub_widget = TextWidget:new{
            text  = sub_txt,
            face  = Font:getFace(SUIStyle.FACE_REGULAR, math.max(9, math.floor(11 * scale * lbl_scale))),
            fgcolor = Blitbuffer.gray(0.3),
        }

        local cell = VerticalGroup:new{
            align = "center",
            cover_widget,
            VerticalSpan:new{ width = Screen:scaleBySize(3) },
            sub_widget,
        }

        -- Wrap in tap container
        local cell_input = InputContainer:new{
            cell,
            gesture_map = {
                tap = {
                    GestureRange:new{
                        range = cell:getSize(),
                        handler = function()
                            local sw_inst = getSuwayomiPlugin()
                            if sw_inst and sw_inst.showUpdates then
                                sw_inst:showUpdates()
                            elseif sw_inst and sw_inst.openFeedEntry then
                                sw_inst:openFeedEntry(entry)
                            elseif sw_inst and sw_inst.showHistory then
                                sw_inst:showHistory()
                            end
                            return true
                        end,
                    }
                }
            }
        }
        item_group[#item_group + 1] = cell_input
    end

    if count == 0 then
        -- Empty state placeholder
        item_group[#item_group + 1] = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = rh },
            TextWidget:new{
                text = _("No recent Suwayomi manga updates."),
                face = Font:getFace(SUIStyle.FACE_ITALIC, math.max(12, math.floor(14 * scale))),
                fgcolor = Blitbuffer.gray(0.5),
            }
        }
    end

    local content = item_group
    local show_frame = RowRenderer and RowRenderer.showFrame and RowRenderer.showFrame(pfx, MOD_ID)
    local solid_bg   = RowRenderer and RowRenderer.solidBg and RowRenderer.solidBg(pfx, MOD_ID)
    local has_box    = show_frame or solid_bg
    local border_sz  = show_frame and SUIStyle.BORDER_SZ or 0
    local radius     = has_box and math.floor(Screen:scaleBySize(12) * scale) or 0
    local border_color = Blitbuffer.gray(0.72)

    return FrameContainer:new{
        bordersize = border_sz,
        radius     = radius,
        color      = border_color,
        background = solid_bg and Blitbuffer.COLOR_WHITE or nil,
        padding    = PAD,
        padding_top = has_box and PAD or 0,
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

    local max_items = 5
    local w = (_ctx and (_ctx.col_w or _ctx.inner_w)) or (Screen:getWidth() - UI.SIDE_PAD * 2)
    local inner_w = w - PAD * 2
    local autofit_cw = math.max(1, math.floor((inner_w - (max_items - 1) * PAD) / max_items))
    local cs = scale * thumb_scale
    local cw = (cs == 1.0) and autofit_cw or math.max(1, math.floor(autofit_cw * cs))
    local rh = math.max(1, math.floor(cw * (D.RECENT_H / D.RECENT_W)))

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

    items[#items + 1] = {
        text           = _lc("Refresh Updates"),
        keep_menu_open = true,
        callback       = function()
            _updates_cache = nil
            _updates_cache_time = 0
            fetchUpdatesEntriesAsync(function()
                refresh()
            end)
        end,
    }

    return items
end

function M.reset()
    _updates_cache = nil
    _updates_cache_time = 0
end

return M
