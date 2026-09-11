-- module_suwayomi_categories.lua — MaxOutUI
-- Suwayomi Categories home module: displays the user's Suwayomi library categories as a
-- horizontally scrollable row of tap buttons. Tapping a category opens that category's
-- manga list via suwayomiplus (showLibraryByCategory), or falls back to showLibrary().

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
local TextWidget      = require("ui/widget/textwidget")

local _ = require("mui_i18n").translate
local Config      = require("mui_config")
local UI          = require("mui_core")
local SUISettings = require("mui_store")
local SUIStyle    = require("mui_style")
local RowRenderer = require("desktop_modules/mui_book_row")
local SwBridge    = require("desktop_modules/suwayomi_bridge")

local PAD    = UI.PAD
local MOD_ID = "suwayomi_categories"

local M = {}
M.id          = MOD_ID
M.name        = _("Manga Categories (Suwayomi)")
M.label       = _("My Categories")
M.default_on  = false
M.enabled_key = MOD_ID .. "_enabled"

-- Module-level cache (5-minute TTL)
local _categories_cache      = nil
local _categories_cache_time = 0

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function getSuwayomiPlugin()
    return SwBridge.getSuwayomiPlugin()
end

local function getSuwayomiSettings()
    local ok, st = pcall(require, "suwayomi/settings")
    return ok and st or nil
end

--- Trigger a homescreen refresh after background data arrives.
local function _triggerHSRefresh()
    local HS      = package.loaded["mui_homescreen"]
    local hs_inst = HS and HS._instance
    if not hs_inst then return end
    pcall(function()
        if hs_inst._refreshImmediate then
            hs_inst:_refreshImmediate(true)
        else
            UIManager:setDirty(hs_inst, "ui")
        end
    end)
end

--- Asynchronously fetch library categories from Suwayomi; caches result for 5 minutes.
local function fetchCategoriesAsync(callback)
    local now = os.time()
    if _categories_cache and (now - _categories_cache_time < 300) then
        if callback then callback(_categories_cache) end
        return
    end

    local sw = getSuwayomiPlugin()
    if not sw or not sw.getClient then
        if callback then callback(_categories_cache or {}) end
        return
    end

    local ok_nrj, NetworkRequestJob = pcall(function()
        return package.loaded["suwayomi/network/request_job"] or require("suwayomi/network/request_job")
    end)
    if not ok_nrj or not NetworkRequestJob then
        if callback then callback(_categories_cache or {}) end
        return
    end

    local SuwayomiSettings = getSuwayomiSettings()
    local credentials      = SuwayomiSettings and SuwayomiSettings:load()

    if not credentials or not credentials.server_url or credentials.server_url == "" then
        if callback then callback(_categories_cache or {}) end
        return
    end

    NetworkRequestJob.start({
        owner           = sw,
        credentials     = credentials,
        request         = { action = "fetch_library_categories" },
        timeout_seconds = 10,
        on_finish = function(result)
            if result and result.ok and result.categories then
                _categories_cache      = result.categories
                _categories_cache_time = os.time()
                _triggerHSRefresh()
                if callback then callback(_categories_cache) end
            else
                if callback then callback(_categories_cache or {}) end
            end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

function M.build(w, ctx)
    local pfx   = ctx and ctx.pfx or ""
    local scale  = Config.getModuleScale(MOD_ID, pfx)

    -- Button height scales with module scale
    local btn_h  = math.max(28, math.floor(Screen:scaleBySize(36) * scale))
    local inner_w = w - PAD * 2

    -- Fire async fetch; homescreen redraws when data arrives
    fetchCategoriesAsync(function() end)

    local categories = _categories_cache or {}
    local row        = HorizontalGroup:new{ align = "center" }

    if #categories == 0 then
        -- Empty state
        row[#row + 1] = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = btn_h },
            TextWidget:new{
                text    = _("No categories yet"),
                face    = Font:getFace(SUIStyle.FACE_ITALIC, math.max(12, math.floor(14 * scale))),
                fgcolor = Blitbuffer.gray(0.5),
            }
        }
    else
        for i, category in ipairs(categories) do
            if i > 1 then
                row[#row + 1] = HorizontalSpan:new{ width = PAD }
            end

            local cat_name = category.name or ("Category " .. tostring(category.id or i))
            local face     = Font:getFace(SUIStyle.FACE_REGULAR, math.max(11, math.floor(13 * scale)))

            -- Measure text to compute a fitting button width
            local tw_probe = TextWidget:new{ text = cat_name, face = face }
            local text_w   = tw_probe:getSize().w
            tw_probe:free()
            local btn_w = text_w + PAD * 3

            local btn = FrameContainer:new{
                width      = btn_w,
                height     = btn_h,
                bordersize = 1,
                radius     = math.floor(btn_h / 2),
                color      = Blitbuffer.gray(0.7),
                padding    = PAD / 2,
                CenterContainer:new{
                    dimen = Geom:new{ w = btn_w - PAD, h = btn_h - PAD },
                    TextWidget:new{
                        text    = cat_name,
                        face    = face,
                        fgcolor = Blitbuffer.gray(0.1),
                    }
                }
            }

            local cat_ref = category   -- stable upvalue per iteration
            row[#row + 1] = SwBridge.makeTappable(btn, btn_w, btn_h, function()
                local sw_inst = SwBridge.requireSuwayomi()
                if not sw_inst then return end
                if sw_inst.showLibraryByCategory then
                    sw_inst:showLibraryByCategory(cat_ref)
                elseif sw_inst.showLibrary then
                    sw_inst:showLibrary()
                end
            end)
        end
    end

    local show_frame = RowRenderer and RowRenderer.showFrame and RowRenderer.showFrame(pfx, MOD_ID)
    local solid_bg   = RowRenderer and RowRenderer.solidBg   and RowRenderer.solidBg(pfx, MOD_ID)
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
        row,
    }
end

function M.getHeight(_ctx)
    local pfx  = _ctx and _ctx.pfx or ""
    local scale = Config.getModuleScale(MOD_ID, pfx)
    local btn_h = math.max(28, math.floor(Screen:scaleBySize(36) * scale))
    local h     = btn_h
    if RowRenderer and (RowRenderer.showFrame(pfx, MOD_ID) or RowRenderer.solidBg(pfx, MOD_ID)) then
        h = h + PAD * 2
    end
    return Config.getScaledLabelH() + h
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

    items[#items + 1] = Config.makeLabelToggleItem(MOD_ID, M.label, refresh, _lc)

    items[#items + 1] = {
        text           = _lc("Refresh Categories"),
        keep_menu_open = true,
        callback       = function()
            _categories_cache      = nil
            _categories_cache_time = 0
            fetchCategoriesAsync(function() refresh() end)
        end,
    }

    return items
end

function M.reset()
    _categories_cache      = nil
    _categories_cache_time = 0
end

return M
