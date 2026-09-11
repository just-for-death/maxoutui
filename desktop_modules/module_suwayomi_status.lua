-- module_suwayomi_status.lua — Simple UI
-- Suwayomi Reading Status home module: compact summary showing total manga in
-- library, total unread chapters, and last sync time.
--
-- Data is sourced from module_suwayomi_library's getCacheStats() when that
-- module is already loaded (shared via package.loaded), so no extra network
-- request is made when both modules are active. Each stat card falls back to
-- "—" when data is unavailable.

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
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")

local _ = require("mui_i18n").translate
local Config      = require("mui_config")
local UI          = require("mui_core")
local SUISettings = require("mui_store")
local SUIStyle    = require("mui_style")
local RowRenderer = require("desktop_modules/mui_book_row")

local PAD    = UI.PAD
local MOD_ID = "suwayomi_status"

local M = {}
M.id          = MOD_ID
M.name        = _("Reading Status (Suwayomi)")
M.label       = _("Reading Status")
M.default_on  = false
M.enabled_key = MOD_ID .. "_enabled"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Pull stats from module_suwayomi_library's shared cache (zero network cost).
--- Returns { total_manga, total_unread, cache_time } or nil.
local function getLibraryStats()
    local lib_mod = package.loaded["desktop_modules/module_suwayomi_library"]
    if lib_mod and lib_mod.getCacheStats then
        local ok, stats = pcall(lib_mod.getCacheStats)
        if ok then return stats end
    end
    return nil
end

--- Format a POSIX timestamp into a human-readable "Xm ago" / "Xh ago" string.
--- Returns "—" when cache_time is 0 or nil.
local function formatSyncTime(cache_time)
    if not cache_time or cache_time == 0 then return "—" end
    local delta = os.time() - cache_time
    if delta < 60 then
        return _("just now")
    elseif delta < 3600 then
        local mins = math.floor(delta / 60)
        return mins .. _("m ago")
    elseif delta < 86400 then
        local hrs = math.floor(delta / 3600)
        return hrs .. _("h ago")
    else
        local days = math.floor(delta / 86400)
        return days .. _("d ago")
    end
end

--- Build a single stat card (VerticalGroup: big number + small label).
local function buildStatCard(card_w, card_h, value_str, label_str, scale)
    local val_face   = Font:getFace(SUIStyle.FACE_BOLD or SUIStyle.FACE_REGULAR,
                                    math.max(16, math.floor(20 * scale)))
    local lbl_face   = Font:getFace(SUIStyle.FACE_REGULAR,
                                    math.max(9,  math.floor(11 * scale)))
    local inner_h    = math.floor(card_h * 0.9)
    local val_h      = math.floor(inner_h * 0.55)
    local lbl_h      = inner_h - val_h

    local card = FrameContainer:new{
        width      = card_w,
        height     = card_h,
        bordersize = 1,
        radius     = math.floor(Screen:scaleBySize(8) * scale),
        color      = Blitbuffer.gray(0.75),
        background = Blitbuffer.gray(0.96),
        padding    = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = card_w, h = card_h },
            VerticalGroup:new{
                align = "center",
                CenterContainer:new{
                    dimen = Geom:new{ w = card_w - PAD, h = val_h },
                    TextWidget:new{
                        text    = value_str,
                        face    = val_face,
                        fgcolor = Blitbuffer.gray(0.05),
                    }
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = card_w - PAD, h = lbl_h },
                    TextWidget:new{
                        text    = label_str,
                        face    = lbl_face,
                        fgcolor = Blitbuffer.gray(0.35),
                    }
                },
            }
        }
    }
    return card
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

function M.build(w, ctx)
    local pfx   = ctx and ctx.pfx or ""
    local scale  = Config.getModuleScale(MOD_ID, pfx)

    local card_h  = math.max(48, math.floor(Screen:scaleBySize(60) * scale))
    local inner_w = w - PAD * 2
    -- Three cards with two gaps between them
    local card_w  = math.max(50, math.floor((inner_w - PAD * 2) / 3))

    -- Read cached stats from the library module (no network call)
    local stats = getLibraryStats()

    local manga_val  = stats and tostring(stats.total_manga)  or "—"
    local unread_val = stats and tostring(stats.total_unread) or "—"
    local sync_val   = stats and formatSyncTime(stats.cache_time) or "—"

    local row = HorizontalGroup:new{ align = "center" }

    row[#row + 1] = buildStatCard(card_w, card_h, manga_val,  _("Manga"),  scale)
    row[#row + 1] = HorizontalSpan:new{ width = PAD }
    row[#row + 1] = buildStatCard(card_w, card_h, unread_val, _("Unread"), scale)
    row[#row + 1] = HorizontalSpan:new{ width = PAD }
    row[#row + 1] = buildStatCard(card_w, card_h, sync_val,   _("Synced"), scale)

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
    local pfx   = _ctx and _ctx.pfx or ""
    local scale  = Config.getModuleScale(MOD_ID, pfx)
    local card_h = math.max(48, math.floor(Screen:scaleBySize(60) * scale))
    local h      = card_h
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

    -- Trigger a library refresh via the library module if loaded
    items[#items + 1] = {
        text           = _lc("Refresh Stats"),
        keep_menu_open = true,
        callback       = function()
            local lib_mod = package.loaded["desktop_modules/module_suwayomi_library"]
            if lib_mod and lib_mod.reset then
                lib_mod.reset()
            end
            refresh()
        end,
    }

    return items
end

return M
