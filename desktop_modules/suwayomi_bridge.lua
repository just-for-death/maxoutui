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

-- Cap concurrent thumbnail SubprocessJob downloads across home modules.
M._thumb_inflight = 0
M.MAX_THUMB_JOBS = 2

--- Run `fn` only if under the thumbnail concurrency cap.
-- `fn` must call the returned `done` callback (or the wrapped on_finish) when
-- the job finishes so the slot is released. Returns false if at capacity.
-- Preferred usage with SubprocessJob:
--   SwBridge.startThumbJob(function(done)
--       SubprocessJob.start({ ..., on_finish = function(...) done(); ... end })
--   end)
function M.startThumbJob(fn)
    if type(fn) ~= "function" then return false end
    if M._thumb_inflight >= M.MAX_THUMB_JOBS then return false end
    M._thumb_inflight = M._thumb_inflight + 1
    local finished = false
    local function done()
        if finished then return end
        finished = true
        M._thumb_inflight = math.max(0, M._thumb_inflight - 1)
    end
    local ok = pcall(fn, done)
    if not ok then
        done()
        return false
    end
    return true
end

-- Debounced per-module homescreen slot refresh. Avoids full-page
-- _refreshImmediate (which rebuilds quote/clock/stats too) when Suwayomi
-- library/updates/history data or thumbnails arrive.
M._slot_refresh_pending = {}

--- Refresh only one homescreen module slot (is_book_mod surgical path).
-- @param mod_id string module id (e.g. "suwayomi_library")
-- @param opts optional { debounce = seconds } — coalesce rapid thumb arrivals
function M.refreshHomescreenModule(mod_id, opts)
    if not mod_id or mod_id == "" then return end
    opts = opts or {}
    local debounce = tonumber(opts.debounce) or 0

    local function do_refresh()
        M._slot_refresh_pending[mod_id] = nil
        local HS = package.loaded["mui_homescreen"]
        local hs = HS and HS._instance
        if not hs then return end
        local ok = false
        if hs._refreshBookModSlot then
            ok = hs:_refreshBookModSlot(mod_id)
        end
        if not ok then
            -- Slot missing (module off-page / not built yet): dirty only —
            -- never fall back to full-page rebuild for background data.
            UIManager:setDirty(hs, "ui")
        end
    end

    if debounce > 0 then
        if M._slot_refresh_pending[mod_id] then return end
        M._slot_refresh_pending[mod_id] = true
        UIManager:scheduleIn(debounce, do_refresh)
    else
        pcall(do_refresh)
    end
end

--- Wrap a child widget so taps work after layout (same pattern as mui_book_row).
-- @param child widget
-- @param w number width in pixels
-- @param h number height in pixels
-- @param on_tap function()
-- @param on_hold optional function()
function M.makeTappable(child, w, h, on_tap, on_hold)
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
    if on_hold then
        tappable.ges_events.HoldSuwayomi = {
            GestureRange:new{
                ges = "hold",
                range = function()
                    return tappable.dimen
                end,
            },
        }
        function tappable:onHoldSuwayomi()
            on_hold()
            return true
        end
    end
    function tappable:onTapSuwayomi()
        if on_tap then
            on_tap()
        end
        return true
    end
    return tappable
end

return M
