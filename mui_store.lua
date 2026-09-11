-- mui_store.lua — MaxOutUI dedicated settings store.
--
-- Settings are persisted to:
--   DataStorage:getSettingsDir() .. "/maxoutui/mui_settings.lua"
--
-- On first open after the SimpleUI → MaxOutUI rebrand, this module:
--   1. Moves settings/simpleui/ → settings/maxoutui/ (sui_* → mui_* names)
--   2. Renames every simpleui_* key to maxoutui_*
-- so existing homescreen / pin / style data survives without re-setup.
--
-- Public API — colon syntax (consistent with G_reader_settings):
--
--   SUISettings:get(key)              → value or nil
--   SUISettings:set(key, value)       → (saves immediately)
--   SUISettings:del(key)              → (removes key)
--   SUISettings:isTrue(key)           → boolean  (nil → false)
--   SUISettings:nilOrTrue(key)        → boolean  (nil → true)
--   SUISettings:flush()               → force-write to disk
--   SUISettings:readSetting / saveSetting / delSetting  (aliases)

local logger = require("logger")

local _settings_path = nil
local _store = nil
local _rebrand_done = false

local function _movePath(lfs, ffiutil, src, dst)
    if not src or not dst or src == dst then return end
    if lfs.attributes(src, "mode") == nil then return end
    if lfs.attributes(dst, "mode") ~= nil then return end
    if os.rename(src, dst) then return end
    if lfs.attributes(src, "mode") == "file" and ffiutil and ffiutil.copyFile then
        if ffiutil.copyFile(src, dst) then
            os.remove(src)
        end
    end
end

local function _ensureDir(lfs, path)
    if lfs.attributes(path, "mode") ~= "directory" then
        lfs.mkdir(path)
    end
end

-- One-time filesystem rebrand before the settings file is opened.
local function _migrateUserDataTree()
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (ok_ds and ok_lfs and DataStorage and lfs) then return end
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if not ok_ffi then ffiutil = nil end

    local settings_dir = DataStorage:getSettingsDir()
    local old_base = settings_dir .. "/simpleui"
    local new_base = settings_dir .. "/maxoutui"
    _ensureDir(lfs, new_base)

    if lfs.attributes(old_base, "mode") == "directory" then
        local renames = {
            { old_base .. "/sui_settings.lua",     new_base .. "/mui_settings.lua" },
            { old_base .. "/sui_settings.lua.old", new_base .. "/mui_settings.lua.old" },
            { old_base .. "/sui_icons",            new_base .. "/mui_icons" },
            { old_base .. "/sui_quotes",           new_base .. "/mui_quotes" },
            { old_base .. "/sui_wallpapers",       new_base .. "/mui_wallpapers" },
            { old_base .. "/sui_presets",          new_base .. "/mui_presets" },
        }
        for _, pair in ipairs(renames) do
            _movePath(lfs, ffiutil, pair[1], pair[2])
        end
        for name in lfs.dir(old_base) do
            if name ~= "." and name ~= ".." then
                _movePath(lfs, ffiutil, old_base .. "/" .. name, new_base .. "/" .. name)
            end
        end
        -- Drop empty leftover tree (ignore failure if non-empty).
        lfs.rmdir(old_base)
    end

    -- If maxoutui still has the old filename, rename it.
    local legacy = new_base .. "/sui_settings.lua"
    local modern = new_base .. "/mui_settings.lua"
    if lfs.attributes(legacy, "mode") == "file" and lfs.attributes(modern, "mode") ~= "file" then
        _movePath(lfs, ffiutil, legacy, modern)
    end
end

local function _getPath()
    if _settings_path then return _settings_path end
    if not _rebrand_done then
        pcall(_migrateUserDataTree)
        _rebrand_done = true
    end
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_ds and DataStorage then
        _settings_path = DataStorage:getSettingsDir() .. "/maxoutui/mui_settings.lua"
    else
        local src = debug.getinfo(1, "S").source or "@./"
        local dir = src:sub(1, 1) == "@" and src:sub(2):match("^(.*)/[^/]+$") or "."
        _settings_path = dir .. "/mui_settings.lua.data"
        logger.warn("maxoutui/mui_settings: DataStorage unavailable, using fallback path:", _settings_path)
    end
    return _settings_path
end

local function _renameSimpleuiKeys(store)
    if not store or type(store.data) ~= "table" then return end
    if store.data.maxoutui_keys_rebranded_v1 then return end
    local to_rename = {}
    for k, v in pairs(store.data) do
        if type(k) == "string" and k:sub(1, 9) == "simpleui_" then
            to_rename[#to_rename + 1] = {
                old = k,
                new = "maxoutui_" .. k:sub(10),
                v = v,
            }
        end
    end
    for _, entry in ipairs(to_rename) do
        if store.data[entry.new] == nil then
            store:saveSetting(entry.new, entry.v)
        end
        store:delSetting(entry.old)
    end
    store:saveSetting("maxoutui_keys_rebranded_v1", true)
    store:flush()
    if #to_rename > 0 then
        logger.info("maxoutui: rebranded", #to_rename, "simpleui_* settings keys")
    end
end

local function _getStore()
    if _store then return _store end
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    if not ok_ls or not LuaSettings then
        logger.warn("maxoutui/mui_settings: LuaSettings unavailable, using in-memory fallback")
        local _mem = {}
        _store = {
            data         = _mem,
            readSetting  = function(_, k, d) local v = _mem[k]; if v == nil then return d end; return v end,
            saveSetting  = function(_, k, v) _mem[k] = v end,
            delSetting   = function(_, k)    _mem[k] = nil end,
            flush        = function() end,
        }
        return _store
    end
    local path = _getPath()
    _store = LuaSettings:open(path)
    pcall(_renameSimpleuiKeys, _store)
    logger.dbg("maxoutui/mui_settings: opened", path)
    return _store
end

local SUISettings = {}

function SUISettings:get(key, default_value)
    return _getStore():readSetting(key, default_value)
end

function SUISettings:set(key, value)
    if value == nil then
        _getStore():delSetting(key)
    else
        _getStore():saveSetting(key, value)
    end
    if _store then _store:flush() end
end

function SUISettings:setNoFlush(key, value)
    if value == nil then
        _getStore():delSetting(key)
    else
        _getStore():saveSetting(key, value)
    end
end

function SUISettings:delNoFlush(key)
    _getStore():delSetting(key)
end

function SUISettings:del(key)
    _getStore():delSetting(key)
    if _store then _store:flush() end
end

function SUISettings:isTrue(key)
    local v = _getStore():readSetting(key)
    return v == true
end

function SUISettings:nilOrTrue(key)
    local v = _getStore():readSetting(key)
    return v ~= false
end

function SUISettings:flush()
    if _store then
        _store:flush()
    end
end

function SUISettings:readSetting(key, default_value)
    return _getStore():readSetting(key, default_value)
end

function SUISettings:saveSetting(key, value)
    if value == nil then
        _getStore():delSetting(key)
    else
        _getStore():saveSetting(key, value)
    end
    if _store then _store:flush() end
end

function SUISettings:delSetting(key)
    _getStore():delSetting(key)
    if _store then _store:flush() end
end

function SUISettings:iterateKeys()
    local data = _getStore().data
    if type(data) ~= "table" then
        return function() end
    end
    return next, data, nil
end

function SUISettings._resetPathCache()
    _settings_path = nil
    _store = nil
    _rebrand_done = false
end

-- ---------------------------------------------------------------------------
-- DeletedBooks — finished books removed from the device (homescreen counts).
-- ---------------------------------------------------------------------------

local STORE_KEY = "maxoutui_deleted_books"

local DeletedBooks = {}

function DeletedBooks.isEnabled()
    return SUISettings:nilOrTrue("maxoutui_preserve_deleted_books_in_stats")
end

local function _loadDeleted()
    return SUISettings:get(STORE_KEY) or {}
end

local function _saveDeleted(tbl)
    SUISettings:set(STORE_KEY, tbl)
end

function DeletedBooks.add(md5, title, authors, year)
    if not md5 then return end
    local tbl = _loadDeleted()
    tbl[md5] = {
        title   = title   or "",
        authors = authors or "",
        year    = year    or 0,
    }
    _saveDeleted(tbl)
end

function DeletedBooks.removeByMd5(md5)
    if not md5 then return end
    local tbl = _loadDeleted()
    if tbl[md5] == nil then return end
    tbl[md5] = nil
    _saveDeleted(tbl)
end

function DeletedBooks.getAll()
    return _loadDeleted()
end

SUISettings.DeletedBooks = DeletedBooks

return SUISettings
