-- login dialog with optional logo at the top
-- place logo.png in the plugin folder to show it above the form

local MultiInputDialog = require("ui/widget/multiinputdialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local _ = require("gettext")

local LoginDialog = {}

-- tries to build a centered logo widget from logo.png in the plugin folder
-- returns nil if the file doesn't exist so callers can skip it safely
local function buildLogoWidget(plugin_path, width)
    local logo_path = plugin_path .. "/logo.png"
    local f = io.open(logo_path, "r")
    if not f then return nil end
    f:close()

    local logo_height = Screen:scaleBySize(70)
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = logo_height },
        ImageWidget:new{
            file = logo_path,
            width = Screen:scaleBySize(140),
            height = Screen:scaleBySize(55),
            scale_for_dpi = true,
        },
    }
end

-- shows the login dialog and calls onLogin(email, password) when the user submits
-- plugin_path is used to find logo.png
function LoginDialog.show(plugin_path, onLogin)
    local dialog_width = math.min(Screen:getWidth() * 0.85, Screen:scaleBySize(440))
    local logo = buildLogoWidget(plugin_path, dialog_width)

    local dialog
    dialog = MultiInputDialog:new{
        title = logo and "" or _("MediaTracker"),  -- hide title text when logo is shown
        fields = {
            {
                hint = _("Email"),
                text = "",
                text_type = "text",
            },
            {
                hint = _("Contraseña"),
                text = "",
                text_type = "password",
            },
        },
        buttons = {{
            {
                text = _("Cancelar"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Iniciar sesión"),
                is_enter_default = true,
                callback = function()
                    local fields = dialog:getFields()
                    local email = fields[1]
                    local password = fields[2]
                    UIManager:close(dialog)
                    if email == "" or password == "" then
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{
                            text = _("Por favor introduce email y contraseña"),
                            timeout = 3,
                        })
                        return
                    end
                    onLogin(email, password)
                end,
            },
        }},
    }

    -- if a logo was loaded, insert it at the top of the dialog's widget tree
    -- this reaches into MultiInputDialog internals so it may need adjustment
    -- on future KOReader versions, but avoids reimplementing input handling
    if logo then
        local frame = dialog[1] and dialog[1][1]
        if frame and frame[1] then
            local content = frame[1]
            -- prepend logo + separator line before the existing content
            local line = LineWidget:new{
                dimen = Geom:new{ w = dialog_width, h = Screen:scaleBySize(1) },
            }
            table.insert(content, 1, line)
            table.insert(content, 1, logo)
            -- trigger a re-layout so the new items are measured
            content:resetLayout()
        end
    end

    UIManager:show(dialog)
end

return LoginDialog
