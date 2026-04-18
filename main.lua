local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local _ = require("gettext")

local MediaTracker = WidgetContainer:extend{
    name = "mediatracker",
    is_doc_only = false,
}

function MediaTracker:init()
    self.Api = dofile(self.path .. "/api.lua")
    self.LoginDialog = dofile(self.path .. "/login_dialog.lua")

    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/mediatracker.lua")
    self.token = self.settings:readSetting("token")
    self.ui.menu:registerToMainMenu(self)

    self:hookBookStatusWidget()
end

-- patch BookStatusWidget so we get notified whenever the user marks any book
-- as finished, regardless of whether they do it from inside the reader or
-- from the file browser / history screen
function MediaTracker:hookBookStatusWidget()
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
                and bsw.props.title or "Desconocido"

            -- page count can live under different keys depending on KOReader version
            local pages = 1
            if bsw.doc_settings then
                pages = bsw.doc_settings:readSetting("doc_pages")
                    or bsw.doc_settings:readSetting("number_of_pages")
                    or 1
            end
            if pages < 1 then pages = 1 end

            -- skip if we already synced this book before
            if bsw.doc_settings and bsw.doc_settings:readSetting("mediatracker_synced") then
                return
            end

            plugin:syncBook(title, pages, bsw.doc_settings)
        end
    end
end

function MediaTracker:syncBook(title, pages, doc_settings)
    local status, response = self.Api.trackBook(self.token, title, pages)

    if status == 200 and response and response.success then
        if doc_settings then
            doc_settings:saveSetting("mediatracker_synced", true)
            doc_settings:flush()
        end
        UIManager:show(InfoMessage:new{
            text = '"' .. title .. '" ' .. _("registrado como finalizado"),
            timeout = 3,
        })
    elseif status == 401 then
        self:saveToken(nil)
        UIManager:show(InfoMessage:new{
            text = _("Sesión expirada. Por favor inicia sesión de nuevo."),
            timeout = 4,
        })
    else
        local msg = (response and response.message) or _("Error desconocido")
        UIManager:show(InfoMessage:new{
            text = _("Error al registrar: ") .. tostring(msg),
            timeout = 4,
        })
    end
end

-- called when the user closes a document without going through the status dialog
-- if they're on the last page we ask if they want to register it as finished
function MediaTracker:onCloseDocument()
    if not self.token then return end
    if not self.ui.document then return end
    if self.ui.doc_settings:readSetting("mediatracker_synced") then return end

    local current_page = self.ui.document:getCurrentPage()
    local total_pages = self.ui.document:getPageCount()
    if not current_page or not total_pages then return end
    if current_page < total_pages then return end

    local props = self.ui.document:getProps()
    local title = (props and props.title and props.title ~= "") and props.title
        or (self.view and self.view.document_title)
        or "Desconocido"

    UIManager:show(ConfirmBox:new{
        text = _("Has llegado al final de \"") .. title .. _("\". ¿Registrarlo como finalizado en MediaTracker?"),
        ok_text = _("Sí"),
        cancel_text = _("No"),
        ok_callback = function()
            self:syncBook(title, total_pages, self.ui.doc_settings)
        end,
    })
end

function MediaTracker:saveToken(token)
    self.token = token
    self.settings:saveSetting("token", token)
    self.settings:flush()
end

function MediaTracker:addToMainMenu(menu_items)
    menu_items.mediatracker = {
        text = _("MediaTracker"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    return self.token and _("Cerrar sesión") or _("Iniciar sesión")
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

function MediaTracker:showLogin()
    self.LoginDialog.show(self.path, function(email, password)
        self:login(email, password)
    end)
end

function MediaTracker:login(email, password)
    local status, response = self.Api.login(email, password)

    if status == 200 and response and response.success then
        self:saveToken(response.token)
        UIManager:show(InfoMessage:new{
            text = _("Sesión iniciada correctamente"),
            timeout = 2,
        })
    else
        local msg = (response and response.message) or _("Error de conexión")
        UIManager:show(InfoMessage:new{
            text = _("Error al iniciar sesión: ") .. tostring(msg),
            timeout = 4,
        })
    end
end

function MediaTracker:logout()
    self:saveToken(nil)
    UIManager:show(InfoMessage:new{
        text = _("Sesión cerrada"),
        timeout = 2,
    })
end

return MediaTracker
