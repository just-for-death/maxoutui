-- module_suwayomi_auto_download.lua — MaxOutUI
-- Homescreen widget for Suwayomi+ auto-download manga (missing / latest).
-- Tap opens manga actions; hold sets mode, downloads now, or removes.

local Device      = require("device")
local Screen      = Device.screen
local Blitbuffer  = require("ffi/blitbuffer")
local Font        = require("ui/font")
local Geom        = require("ui/geometry")
local UIManager   = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local TextWidget      = require("ui/widget/textwidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local ImageWidget     = require("ui/widget/imagewidget")

local _ = require("mui_i18n").translate
local Config      = require("mui_config")
local UI          = require("mui_core")
local SUIStyle    = require("mui_style")
local RowRenderer = require("desktop_modules/mui_book_row")
local SwBridge    = require("desktop_modules/suwayomi_bridge")

local PAD    = UI.PAD
local MOD_ID = "suwayomi_auto_download"

local M = {}
M.id          = MOD_ID
M.name        = _("Auto Download (Suwayomi)")
M.label       = _("Auto Download")
M.default_on  = false
M.enabled_key = MOD_ID .. "_enabled"
M.has_covers  = true
M.is_book_mod = true

local function getSuwayomiPlugin()
    return SwBridge.getSuwayomiPlugin()
end

local function getSuwayomiSettings()
    local ok, st = pcall(require, "suwayomi/settings")
    return ok and st or nil
end

local function getThumbnailCache()
    local ok, tc = pcall(require, "suwayomi/ui/thumbnail_cache")
    return ok and tc or nil
end

local function modeLabel(mode)
    if mode == "latest" then
        return _("Latest")
    end
    return _("Missing")
end

local function loadTrackedList()
    local Settings = getSuwayomiSettings()
    if not Settings or not Settings.loadAutoDownloadManga then
        return {}
    end
    return Settings:loadAutoDownloadManga() or {}
end

local function refreshHome()
    SwBridge.refreshHomescreenModule(MOD_ID)
end

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

local function showMangaHoldMenu(entry)
    local sw = SwBridge.requireSuwayomi()
    if not sw then return end
    local dialog
    dialog = ButtonDialog:new{
        title = entry.title or entry.id,
        buttons = {
            {
                {
                    text = _("Mode: Missing"),
                    callback = function()
                        UIManager:close(dialog)
                        if sw.setAutoDownloadMangaMode then
                            sw:setAutoDownloadMangaMode(entry, "missing")
                        end
                        refreshHome()
                    end,
                },
            },
            {
                {
                    text = _("Mode: Latest"),
                    callback = function()
                        UIManager:close(dialog)
                        if sw.setAutoDownloadMangaMode then
                            sw:setAutoDownloadMangaMode(entry, "latest")
                        end
                        refreshHome()
                    end,
                },
            },
            {
                {
                    text = _("Download now"),
                    callback = function()
                        UIManager:close(dialog)
                        if sw.enqueueAutoDownloadForManga then
                            sw:enqueueAutoDownloadForManga(entry, entry.mode or "missing")
                        end
                    end,
                },
            },
            {
                {
                    text = _("Remove"),
                    callback = function()
                        UIManager:close(dialog)
                        if sw.removeMangaFromAutoDownload then
                            sw:removeMangaFromAutoDownload(entry)
                        end
                        refreshHome()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

local function showAddMangaDialog()
    local sw = SwBridge.requireSuwayomi()
    if not sw then return end

    local Settings = getSuwayomiSettings()
    local tracked = loadTrackedList()
    local tracked_ids = {}
    for _, e in ipairs(tracked) do
        tracked_ids[tostring(e.id)] = true
    end

    local picker
    local function presentPicker(manga_list)
        local buttons = {}
        local count = 0
        for _, manga in ipairs(manga_list or {}) do
            local id = tostring(manga.id or "")
            if id ~= "" and not tracked_ids[id] then
                count = count + 1
                if count > 40 then
                    break
                end
                local title = manga.title or id
                local _manga = manga
                table.insert(buttons, {
                    {
                        text = title,
                        callback = function()
                            if picker then
                                UIManager:close(picker)
                            end
                            local mode_dialog
                            mode_dialog = ButtonDialog:new{
                                title = title,
                                buttons = {
                                    {
                                        {
                                            text = _("Missing chapters"),
                                            callback = function()
                                                UIManager:close(mode_dialog)
                                                sw:addMangaToAutoDownload(_manga, "missing")
                                                refreshHome()
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text = _("Latest chapters"),
                                            callback = function()
                                                UIManager:close(mode_dialog)
                                                sw:addMangaToAutoDownload(_manga, "latest")
                                                refreshHome()
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(mode_dialog)
                        end,
                    },
                })
            end
        end
        if #buttons == 0 then
            UIManager:show(InfoMessage:new{
                text = _("No library manga left to add (or library not loaded yet)."),
                timeout = 4,
            })
            return
        end
        picker = ButtonDialog:new{
            title = _("Add to auto-download"),
            buttons = buttons,
        }
        UIManager:show(picker)
    end

    if sw.getClient and Settings then
        local credentials = Settings:load()
        local NetworkRequestJob = package.loaded["suwayomi/network/request_job"] or require("suwayomi/network/request_job")
        NetworkRequestJob.start({
            owner = sw,
            credentials = credentials,
            request = { action = "fetch_library_manga_pages" },
            timeout_seconds = 30,
            on_finish = function(result)
                if result and result.ok and result.manga then
                    presentPicker(result.manga)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Could not load library manga."),
                        timeout = 3,
                    })
                end
            end,
        })
        return
    end

    presentPicker({})
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

    local manga_list = loadTrackedList()
    local item_group = HorizontalGroup:new{}
    local TC = getThumbnailCache()
    local credentials = getSuwayomiSettings() and getSuwayomiSettings():load()
    if credentials and #manga_list > 0 then
        prefetchThumbnailsAsync(credentials, manga_list)
    end

    local count = 0
    for _, manga in ipairs(manga_list) do
        if count >= max_items then break end
        count = count + 1
        if count > 1 then
            item_group[#item_group + 1] = HorizontalSpan:new{ width = PAD }
        end

        local title = manga.title or "Manga"
        local cover_widget
        local cached_path = TC and credentials and manga.thumbnail_url
            and TC.find(credentials, manga.thumbnail_url, { variant = "thumbnail" })
        local decoded_bmp = cached_path and TC.loadDecoded(cached_path)

        if decoded_bmp then
            cover_widget = ImageWidget:new{
                image = decoded_bmp,
                width = cw,
                height = rh,
                scale_factor = 0,
            }
        else
            cover_widget = FrameContainer:new{
                width = cw,
                height = rh,
                bordersize = 1,
                color = Blitbuffer.gray(0.6),
                background = Blitbuffer.gray(0.9),
                padding = 4,
                CenterContainer:new{
                    dimen = Geom:new{ w = cw - 8, h = rh - 8 },
                    TextBoxWidget:new{
                        text = title,
                        face = Font:getFace(SUIStyle.FACE_REGULAR, math.max(10, math.floor(12 * scale))),
                        width = cw - 8,
                        alignment = "center",
                    },
                },
            }
        end

        local sub_widget = TextWidget:new{
            text = modeLabel(manga.mode),
            face = Font:getFace(SUIStyle.FACE_REGULAR, math.max(9, math.floor(11 * scale * lbl_scale))),
            fgcolor = Blitbuffer.gray(0.3),
        }

        local cell = VerticalGroup:new{
            align = "center",
            cover_widget,
            VerticalSpan:new{ width = Screen:scaleBySize(3) },
            sub_widget,
        }

        local _manga = manga
        local cell_h = rh + Screen:scaleBySize(20)
        item_group[#item_group + 1] = SwBridge.makeTappable(cell, cw, cell_h, function()
            local sw_inst = SwBridge.requireSuwayomi()
            if not sw_inst then return end
            if sw_inst.showMangaActions then
                sw_inst:showMangaActions(_manga)
            elseif sw_inst.showChaptersForManga then
                sw_inst:showChaptersForManga(_manga)
            end
        end, function()
            showMangaHoldMenu(_manga)
        end)
    end

    if count == 0 then
        local empty = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = rh },
            TextWidget:new{
                text = _("No auto-download manga. Tap to add."),
                face = Font:getFace(SUIStyle.FACE_ITALIC, math.max(12, math.floor(14 * scale))),
                fgcolor = Blitbuffer.gray(0.5),
                max_width = inner_w,
            },
        }
        item_group[#item_group + 1] = SwBridge.makeTappable(empty, inner_w, rh, function()
            showAddMangaDialog()
        end)
    end

    local show_frame = RowRenderer and RowRenderer.showFrame and RowRenderer.showFrame(pfx, MOD_ID)
    local solid_bg   = RowRenderer and RowRenderer.solidBg and RowRenderer.solidBg(pfx, MOD_ID)
    local has_box    = show_frame or solid_bg
    local border_sz  = show_frame and SUIStyle.BORDER_SZ or 0
    local radius     = has_box and math.floor(Screen:scaleBySize(12) * scale) or 0

    return FrameContainer:new{
        bordersize     = border_sz,
        radius         = radius,
        color          = Blitbuffer.gray(0.72),
        background     = solid_bg and Blitbuffer.COLOR_WHITE or nil,
        padding        = PAD,
        padding_top    = has_box and PAD or 0,
        padding_bottom = has_box and PAD or 0,
        item_group,
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
    local credentials = getSuwayomiSettings() and getSuwayomiSettings():load()
    local list = loadTrackedList()
    if credentials and #list > 0 then
        prefetchThumbnailsAsync(credentials, list)
    end
    return true
end

function M.getMenuItems(ctx_menu)
    local _lc = ctx_menu._
    local refresh = ctx_menu.refresh
    local pfx = ctx_menu.pfx
    local items = {}

    items[#items + 1] = {
        text = _lc("Add manga…"),
        keep_menu_open = true,
        callback = function()
            showAddMangaDialog()
            refresh()
        end,
    }
    items[#items + 1] = {
        text = _lc("Download all now"),
        keep_menu_open = true,
        callback = function()
            local sw = SwBridge.requireSuwayomi()
            if sw and sw.syncAllAutoDownloadManga then
                sw:syncAllAutoDownloadManga()
            end
        end,
    }
    items[#items + 1] = {
        text = _lc("Manage in Suwayomi+"),
        keep_menu_open = true,
        callback = function()
            local sw = SwBridge.requireSuwayomi()
            if sw and sw.showAutoDownloadMangaManager then
                sw:showAutoDownloadMangaManager({ refresh = refresh })
            end
        end,
    }

    items[#items + 1] = Config.makeScaleItem{
        text_func = function() return _lc("Scale") end,
        enabled_func = function() return not Config.isScaleLinked() end,
        title = _lc("Scale"),
        info = _lc("Scale for this module.\n100% is the default size."),
        get = function() return Config.getModuleScalePct(MOD_ID, pfx) end,
        set = function(v) Config.setModuleScale(v, MOD_ID, pfx) end,
        refresh = refresh,
    }
    items[#items + 1] = Config.makeScaleItem{
        text_func = function() return _lc("Cover Size") end,
        separator = true,
        title = _lc("Cover Size"),
        info = _lc("Scale for the cover thumbnails.\n100% is the default size."),
        get = function() return Config.getThumbScalePct(MOD_ID, pfx) end,
        set = function(v) Config.setThumbScale(v, MOD_ID, pfx) end,
        refresh = refresh,
    }
    items[#items + 1] = Config.makeLabelToggleItem(MOD_ID, M.label, refresh, _lc)
    return items
end

function M.reset()
end

return M
