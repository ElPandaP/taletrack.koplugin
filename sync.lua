-- Offline queue for book-progress syncs.
-- Holds at most one entry per book (the latest / highest progress) and flushes
-- to the backend when there's a network connection. Persisted to its own file so
-- writing it is cheap and never touches auth state.

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")

local MAX_ITEMS = 100
local MAX_AGE = 4 * 7 * 24 * 60 * 60 -- 4 weeks, in seconds

local Sync = {}
Sync.__index = Sync

-- Epoch time, or nil if the device clock looks bogus (e-reader RTCs drift badly).
local function sane_now()
    local t = os.time()
    if type(t) == "number" and t > 1600000000 then return t end
    return nil
end

-- opts = { api, get_tokens, set_tokens, path? }
--   api          : the api.lua module
--   get_tokens() : returns access, refresh
--   set_tokens(access, refresh) : persists a rotated token pair
function Sync.new(opts)
    local self = setmetatable({}, Sync)
    self.api = opts.api
    self.get_tokens = opts.get_tokens
    self.set_tokens = opts.set_tokens
    self.store = LuaSettings:open(
        opts.path or (DataStorage:getSettingsDir() .. "/taletrack_queue.lua"))
    self.items = self.store:readSetting("items") or {}
    self.dirty = false
    return self
end

-- item = { key, title, pages, progress (1-100), author?, isbn? }
function Sync:enqueue(item)
    if not item.key or not item.title then return end
    if not item.progress or item.progress < 1 then return end

    local kept, prev = {}, 0
    for _, it in ipairs(self.items) do
        if it.key == item.key then
            prev = it.progress or 0
        else
            kept[#kept + 1] = it
        end
    end

    item.progress = math.max(item.progress, prev)
    item.ts = sane_now()
    kept[#kept + 1] = item
    self.items = kept
    self:prune()
    self.dirty = true
end

function Sync:prune()
    local now = sane_now()
    if now then
        local cutoff = now - MAX_AGE
        local kept = {}
        for _, it in ipairs(self.items) do
            if not it.ts or it.ts >= cutoff then kept[#kept + 1] = it end
        end
        self.items = kept
    end
    while #self.items > MAX_ITEMS do
        table.remove(self.items, 1)
        self.dirty = true
    end
end

function Sync:count()
    return #self.items
end

function Sync:persist()
    if not self.dirty then return end
    self.store:saveSetting("items", self.items)
    self.store:flush()
    self.dirty = false
end

-- Sends one item. Returns "ok" | "auth" | "retry" | "drop".
function Sync:send(item)
    local access, refresh = self.get_tokens()
    if not access then return "auth" end

    local status, response = self.api.trackBook(access, item)

    if status == 401 and refresh then
        local rstatus, rbody = self.api.refresh(refresh)
        if rstatus == 200 and rbody and rbody.token then
            self.set_tokens(rbody.token, rbody.refreshToken or refresh)
            status, response = self.api.trackBook(rbody.token, item)
        else
            return "auth"
        end
    end

    if status == 200 and response and response.success then
        return "ok"
    elseif status == 401 then
        return "auth"
    elseif status == nil then
        return "retry" -- transport failure: keep it, try again later
    else
        logger.warn("TaleTrack: dropping queued item, HTTP", status,
            response and response.message)
        return "drop" -- 4xx/5xx we can't fix by retrying
    end
end

-- Drains the queue oldest-first. Stops at the first transient failure.
-- on_status("auth") is called at most once if the session is dead.
function Sync:flush(on_status)
    if #self.items == 0 then return end
    if not NetworkMgr:isConnected() then return end

    local kept, stop, auth_failed = {}, false, false

    for _, item in ipairs(self.items) do
        if stop then
            kept[#kept + 1] = item
        else
            local result = self:send(item)
            if result == "ok" or result == "drop" then
                self.dirty = true
            elseif result == "retry" then
                kept[#kept + 1] = item
                stop = true
            else -- "auth"
                kept[#kept + 1] = item
                auth_failed = true
                stop = true
            end
        end
    end

    self.items = kept
    self:persist()

    if auth_failed and on_status then on_status("auth") end
end

return Sync
