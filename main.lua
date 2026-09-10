local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local TaleTrack = WidgetContainer:extend{
    name = "TaleTrack",
    is_doc_only = false,
}

function TaleTrack:init()
    self.Api = dofile(self.path .. "/api.lua")
    self.LoginDialog = dofile(self.path .. "/login_dialog.lua")

    local i18n = dofile(self.path .. "/i18n.lua").setup()
    self.lang = i18n.lang
    self.t = i18n.t

    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/TaleTrack.lua")
    self.token = self.settings:readSetting("token")
    self.ui.menu:registerToMainMenu(self)

    self:hookBookStatusWidget()
end

-- patch BookStatusWidget so we get notified whenever the user marks any book
-- as finished, regardless of whether they do it from inside the reader or
-- from the file browser / history screen
function TaleTrack:hookBookStatusWidget()
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local plugin = self  -- upvalue so the closure below can reach the plugin
    local original_init = BookStatusWidget.init

    BookStatusWidget.init = function(bsw)
        original_init(bsw)

        local original_callback = bsw.callback
        if not original_callback then return end

        bsw.callback = function(config, ...)
            -- always call the original first so KOReader saves the status normally
            original_callback(config, ...)

            if not (config and config.summary and config.summary.status == "complete") then
                return
            end
            if not plugin.token then return end

            -- get title from the widget's props (set by whoever opens BookStatusWidget)
            local title = (bsw.props and bsw.props.title and bsw.props.title ~= "")
                and bsw.props.title or plugin.t("unknown_book")

            -- page count can live under different keys depending on KOReader version
            local pages = 1
            if bsw.doc_settings then
                pages = bsw.doc_settings:readSetting("doc_pages")
                    or bsw.doc_settings:readSetting("number_of_pages")
                    or 1
            end
            if pages < 1 then pages = 1 end

            -- skip if we already synced this book before
            if bsw.doc_settings and bsw.doc_settings:readSetting("TaleTrack_synced") then
                return
            end

            plugin:syncBook(title, pages, bsw.doc_settings)
        end
    end
end

function TaleTrack:syncBook(title, pages, doc_settings)
    local status, response = self.Api.trackBook(self.token, title, pages)

    if status == 200 and response and response.success then
        if doc_settings then
            doc_settings:saveSetting("TaleTrack_synced", true)
            doc_settings:flush()
        end
        UIManager:show(InfoMessage:new{
            text = '"' .. title .. '" ' .. self.t("registered_finished"),
            timeout = 3,
        })
    elseif status == 401 then
        self:saveToken(nil)
        UIManager:show(InfoMessage:new{
            text = self.t("session_expired"),
            timeout = 4,
        })
    else
        local msg = (response and response.message) or self.t("unknown_error")
        UIManager:show(InfoMessage:new{
            text = self.t("register_error", msg),
            timeout = 4,
        })
    end
end

-- called when the user closes a document without going through the status dialog
-- if they're on the last page we ask if they want to register it as finished
function TaleTrack:onCloseDocument()
    if not self.token then return end
    if not self.ui.document then return end
    if self.ui.doc_settings:readSetting("TaleTrack_synced") then return end

    local current_page = self.ui.document:getCurrentPage()
    local total_pages = self.ui.document:getPageCount()
    if not current_page or not total_pages then return end
    if current_page < total_pages then return end

    local props = self.ui.document:getProps()
    local title = (props and props.title and props.title ~= "") and props.title
        or (self.view and self.view.document_title)
        or self.t("unknown_book")

    UIManager:show(ConfirmBox:new{
        text = self.t("reached_end", title),
        ok_text = self.t("yes"),
        cancel_text = self.t("no"),
        ok_callback = function()
            self:syncBook(title, total_pages, self.ui.doc_settings)
        end,
    })
end

function TaleTrack:saveToken(token)
    self.token = token
    self.settings:saveSetting("token", token)
    self.settings:flush()
end

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
        self:saveToken(response.token)
        UIManager:show(InfoMessage:new{
            text = self.t("signed_in"),
            timeout = 2,
        })
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
    self:saveToken(nil)
    UIManager:show(InfoMessage:new{
        text = self.t("signed_out"),
        timeout = 2,
    })
end

return TaleTrack
