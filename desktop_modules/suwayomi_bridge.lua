-- suwayomi_bridge.lua — shared helpers for MaxOutUI Suwayomi home modules.
--
-- Fixes two bugs in the original modules:
-- 1) Taps used gesture_map + cell:getSize() (broken in KOReader). Working
--    MaxOutUI book rows use ges_events + onTap* + dynamic dimen.
-- 2) Plugin lookup often returned the class table (dofile) instead of the
--    live FileManager/ReaderUI instance.

local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")
local InfoMessage    = require("ui/widget/infomessage")

local M = {}

function M.getSuwayomiPlugin()
    -- Live instances first (KOReader: self.ui[plugin_name]).
    local FM = package.loaded["apps/filemanager/filemanager"]
    local fm = FM and FM.instance
    if fm then
        if fm.suwayomiplus then return fm.suwayomiplus end
        if fm._modules then
            for _, mod in pairs(fm._modules) do
                if type(mod) == "table" and mod.name == "suwayomiplus" then
                    return mod
                end
            end
        end
    end

    local RUI = package.loaded["apps/reader/readerui"]
    local rui = RUI and RUI.instance
    if rui then
        if rui.suwayomiplus then return rui.suwayomiplus end
        if rui._modules then
            for _, mod in pairs(rui._modules) do
                if type(mod) == "table" and mod.name == "suwayomiplus" then
                    return mod
                end
            end
        end
    end

    -- Last resort: any package.loaded entry that looks like a live instance
    -- (must have openSuwayomi / showLibrary — not the bare class table).
    for key, m in pairs(package.loaded) do
        if type(key) == "string" and key:find("suwayomiplus", 1, true) and type(m) == "table" then
            local inst = m.instance or m
            if type(inst) == "table" and (inst.showLibrary or inst.openSuwayomi or inst.resumeMangaStream) then
                return inst
            end
        end
    end
    return nil
end

function M.requireSuwayomi(msg)
    local sw = M.getSuwayomiPlugin()
    if sw then return sw end
    UIManager:show(InfoMessage:new{
        text = msg or "Suwayomi+ is not loaded. Enable the plugin and restart KOReader.",
        timeout = 3,
    })
    return nil
end

--- Wrap a child widget so taps work after layout (same pattern as mui_book_row).
-- @param child widget
-- @param w number width in pixels
-- @param h number height in pixels
-- @param on_tap function()
function M.makeTappable(child, w, h, on_tap)
    local tappable = InputContainer:new{
        dimen = Geom:new{ w = w, h = h },
        [1] = child,
    }
    tappable.ges_events = {
        TapSuwayomi = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return tappable.dimen
                end,
            },
        },
    }
    function tappable:onTapSuwayomi()
        if on_tap then
            on_tap()
        end
        return true
    end
    return tappable
end

return M
