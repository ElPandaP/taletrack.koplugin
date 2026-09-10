local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

-- How often, at most, progress is pushed while actively reading (seconds).
local SYNC_INTERVAL = 120

local TaleTrack = WidgetContainer:extend{
    name = "TaleTrack",
    is_doc_only = false,
}

function TaleTrack:init()
    self.Api = dofile(self.path .. "/api.lua")
    self.LoginDialog = dofile(self.path .. "/login_dialog.lua")
    local Sync = dofile(self.path .. "/sync.lua")

    local i18n = dofile(self.path .. "/i18n.lua").setup()
    self.lang = i18n.lang
    self.t = i18n.t

    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/TaleTrack.lua")
    self.token = self.settings:readSetting("token")
    self.refresh_token = self.settings:readSetting("refresh_token")

    self.sync = Sync.new{
        api = self.Api,
        get_tokens = function() return self.token, self.refresh_token end,
        set_tokens = function(access, refresh) self:saveTokens(access, refresh) end,
    }

    -- One stored reference each, so UIManager:unschedule can cancel them.
    self.sync_task = function()
        self.sync_scheduled = false
        self:syncCurrentProgress()
    end
    self.flush_task = function() self:flushQueue() end

    self.ui.menu:registerToMainMenu(self)
    self:hookBookStatusWidget()

    -- Drain anything left from a previous offline session.
    if self.token then UIManager:scheduleIn(3, self.flush_task) end
end

--------------------------------------------------------------------------------
-- Auth / tokens
--------------------------------------------------------------------------------

function TaleTrack:saveTokens(access, refresh)
    self.token = access
    self.refresh_token = refresh
    if access then
        self.settings:saveSetting("token", access)
    else
        self.settings:delSetting("token")
    end
    if refresh then
        self.settings:saveSetting("refresh_token", refresh)
    else
        self.settings:delSetting("refresh_token")
    end
    self.settings:flush()
end

function TaleTrack:clearAuth()
    self:saveTokens(nil, nil)
end

--------------------------------------------------------------------------------
-- Progress reading + queueing
--------------------------------------------------------------------------------

-- Current reading progress as an integer percent (0-100), or nil.
function TaleTrack:docProgress()
    local doc = self.ui and self.ui.document
    if not doc then return nil end

    local percent
    if doc.info and doc.info.has_pages then
        percent = self.ui.paging and self.ui.paging:getLastPercent()
    else
        percent = self.ui.rolling and self.ui.rolling:getLastPercent()
    end
    if not percent then
        local cur = doc.getCurrentPage and doc:getCurrentPage()
        local total = doc.getPageCount and doc:getPageCount()
        if cur and total and total > 0 then percent = cur / total end
    end
    if not percent then return nil end

    local p = math.floor(percent * 100 + 0.5)
    if p < 0 then p = 0 elseif p > 100 then p = 100 end
    return p
end

function TaleTrack:currentBook()
    local doc = self.ui and self.ui.document
    if not doc then return nil end

    local props = (doc.getProps and doc:getProps()) or {}
    local title = (props.title and props.title ~= "") and props.title
        or (self.view and self.view.document_title)
        or self.t("unknown_book")

    local pages = (doc.getPageCount and doc:getPageCount()) or 1
    if pages < 1 then pages = 1 end

    local key = (self.ui.doc_settings and self.ui.doc_settings:readSetting("partial_md5_checksum"))
        or title:lower()

    return { key = key, title = title, pages = pages }
end

-- Enqueue the given progress for the current book (silent). `progress` defaults
-- to whatever the reader is showing right now.
function TaleTrack:enqueueCurrent(progress)
    if not self.token then return end
    progress = progress or self:docProgress()
    if not progress or progress < 1 then return end
    if progress == self.last_sent_progress then return end

    local book = self:currentBook()
    if not book then return end

    self.sync:enqueue{
        key = book.key,
        title = book.title,
        pages = book.pages,
        progress = progress,
    }
    self.last_sent_progress = progress
end

function TaleTrack:flushQueue()
    if not self.token then return end
    self.sync:flush(function(kind)
        if kind == "auth" then
            self:clearAuth()
            UIManager:show(InfoMessage:new{ text = self.t("session_expired"), timeout = 4 })
        end
    end)
end

function TaleTrack:syncCurrentProgress()
    self:enqueueCurrent()
    UIManager:scheduleIn(0, self.flush_task)
end

--------------------------------------------------------------------------------
-- Reader events (broadcast to all widgets)
--------------------------------------------------------------------------------

function TaleTrack:onReaderReady()
    self.last_sent_progress = nil
    self.sync_scheduled = false
    if self.token then UIManager:scheduleIn(3, self.flush_task) end
end

function TaleTrack:onPageUpdate()
    if not self.token then return end
    if self.sync_scheduled then return end
    self.sync_scheduled = true
    UIManager:scheduleIn(SYNC_INTERVAL, self.sync_task)
end

function TaleTrack:onEndOfBook()
    if not self.token then return end
    self:enqueueCurrent(100)
    UIManager:scheduleIn(0, self.flush_task)
end

function TaleTrack:onCloseDocument()
    UIManager:unschedule(self.sync_task)
    self.sync_scheduled = false
    self:enqueueCurrent()
    self:flushQueue()
    self.sync:persist()
    self.last_sent_progress = nil
end

function TaleTrack:onSuspend()
    UIManager:unschedule(self.sync_task)
    self.sync_scheduled = false
    self:enqueueCurrent()
    self.sync:persist()
end

function TaleTrack:onResume()
    if self.token then UIManager:scheduleIn(1, self.flush_task) end
end

function TaleTrack:onNetworkConnected()
    if self.token then UIManager:scheduleIn(0.5, self.flush_task) end
end

function TaleTrack:onFlushSettings()
    self.sync:persist()
end

--------------------------------------------------------------------------------
-- "Book finished" hook
--------------------------------------------------------------------------------

-- Patch BookStatusWidget so we're notified whenever the user marks any book as
-- finished, from inside the reader or from the file browser / history screen.
function TaleTrack:hookBookStatusWidget()
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local plugin = self
    local original_init = BookStatusWidget.init

    BookStatusWidget.init = function(bsw)
        original_init(bsw)

        local original_callback = bsw.callback
        if not original_callback then return end

        bsw.callback = function(config, ...)
            original_callback(config, ...)

            if not (config and config.summary and config.summary.status == "complete") then
                return
            end
            if not plugin.token then return end

            local title = (bsw.props and bsw.props.title and bsw.props.title ~= "")
                and bsw.props.title or plugin.t("unknown_book")

            local pages = 1
            if bsw.doc_settings then
                pages = bsw.doc_settings:readSetting("doc_pages")
                    or bsw.doc_settings:readSetting("number_of_pages")
                    or 1
            end
            if pages < 1 then pages = 1 end

            local key = (bsw.doc_settings and bsw.doc_settings:readSetting("partial_md5_checksum"))
                or title:lower()

            plugin.sync:enqueue{ key = key, title = title, pages = pages, progress = 100 }
            plugin:flushQueue()

            UIManager:show(InfoMessage:new{
                text = '"' .. title .. '" ' .. plugin.t("registered_finished"),
                timeout = 3,
            })
        end
    end
end

--------------------------------------------------------------------------------
-- Menu + login
--------------------------------------------------------------------------------

function TaleTrack:addToMainMenu(menu_items)
    menu_items.TaleTrack = {
        text = "TaleTrack",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    return self.token and self.t("sign_out") or self.t("sign_in")
                end,
                callback = function()
                    if self.token then
                        self:logout()
                    else
                        self:showLogin()
                    end
                end,
            },
        },
    }
end

-- Two-step OTP login: email -> request a code -> verify it.
function TaleTrack:showLogin()
    self.LoginDialog.showEmailStep(self.t, function(email)
        self:requestCode(email)
    end)
end

function TaleTrack:requestCode(email)
    local status, response = self.Api.requestCode(email, self.lang)

    if status == 200 and response and response.success then
        self.LoginDialog.showCodeStep(self.t, email, function(code)
            self:verifyCode(email, code)
        end, function()
            self:showLogin()
        end)
    else
        local msg = (response and response.message and response.message ~= "" and response.message)
            or self.t("connection_error")
        UIManager:show(InfoMessage:new{
            text = self.t("send_code_error", msg),
            timeout = 4,
        })
    end
end

function TaleTrack:verifyCode(email, code)
    local status, response = self.Api.verifyCode(email, code)

    if status == 200 and response and response.success and response.token then
        self:saveTokens(response.token, response.refreshToken)
        UIManager:show(InfoMessage:new{
            text = self.t("signed_in"),
            timeout = 2,
        })
        UIManager:scheduleIn(1, self.flush_task)
    else
        local msg = (response and response.message and response.message ~= "" and response.message)
            or self.t("code_invalid")
        UIManager:show(InfoMessage:new{
            text = self.t("verify_code_error", msg),
            timeout = 4,
        })
    end
end

function TaleTrack:logout()
    self:clearAuth()
    UIManager:show(InfoMessage:new{
        text = self.t("signed_out"),
        timeout = 2,
    })
end

return TaleTrack
