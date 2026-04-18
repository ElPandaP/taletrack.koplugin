-- two-step OTP login dialog
-- step 1: email input → step 2: 6-digit code verification

local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local LoginDialog = {}

function LoginDialog.showEmailStep(onEmailSubmit)
    local dialog
    dialog = InputDialog:new{
        title = _("TaleTrack - Iniciar sesión"),
        input_hint = _("tu@email.com"),
        input_type = "text",
        buttons = {{
            {
                text = _("Cancelar"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Enviar código"),
                is_enter_default = true,
                callback = function()
                    local email = dialog:getInputText()
                    UIManager:close(dialog)
                    if email == "" then
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{
                            text = _("Por favor introduce tu email"),
                            timeout = 3,
                        })
                        return
                    end
                    onEmailSubmit(email)
                end,
            },
        }},
    }
    UIManager:show(dialog)
end

-- onBack is called when the user wants to re-enter their email
function LoginDialog.showCodeStep(email, onCodeSubmit, onBack)
    local dialog
    dialog = InputDialog:new{
        title = _("Introduce el código"),
        description = _("Código enviado a ") .. email,
        input_hint = _("000000"),
        input_type = "number",
        buttons = {{
            {
                text = _("Volver"),
                callback = function()
                    UIManager:close(dialog)
                    if onBack then onBack() end
                end,
            },
            {
                text = _("Verificar"),
                is_enter_default = true,
                callback = function()
                    local code = dialog:getInputText()
                    UIManager:close(dialog)
                    if code == "" then
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{
                            text = _("Por favor introduce el código"),
                            timeout = 3,
                        })
                        return
                    end
                    onCodeSubmit(code)
                end,
            },
        }},
    }
    UIManager:show(dialog)
end

return LoginDialog
