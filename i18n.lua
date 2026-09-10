-- Minimal English/Spanish strings for the plugin. English keys are the source.
-- The language is read once from KOReader's UI setting; anything that isn't
-- Spanish falls back to English.

local Strings = {
    en = {
        registered_finished  = "recorded as finished",
        session_expired      = "Session expired. Please sign in again.",
        unknown_book         = "Unknown",
        sign_out             = "Sign out",
        sign_in              = "Sign in",
        connection_error     = "Connection error",
        send_code_error      = "Couldn't send the code: {}",
        signed_in            = "Signed in successfully",
        code_invalid         = "Wrong or expired code",
        verify_code_error    = "Couldn't verify the code: {}",
        signed_out           = "Signed out",
        -- login dialog
        login_title          = "TaleTrack · Sign in",
        email_hint           = "you@email.com",
        cancel               = "Cancel",
        send_code            = "Send code",
        enter_email          = "Please enter your email",
        enter_code_title     = "Enter the code",
        code_sent_to         = "Code sent to {}",
        code_hint            = "000000",
        back                 = "Back",
        verify               = "Verify",
        enter_code           = "Please enter the code",
    },
    es = {
        registered_finished  = "registrado como finalizado",
        session_expired      = "Sesión expirada. Por favor inicia sesión de nuevo.",
        unknown_book         = "Desconocido",
        sign_out             = "Cerrar sesión",
        sign_in              = "Iniciar sesión",
        connection_error     = "Error de conexión",
        send_code_error      = "Error al enviar el código: {}",
        signed_in            = "Sesión iniciada correctamente",
        code_invalid         = "Código incorrecto o caducado",
        verify_code_error    = "Error al verificar el código: {}",
        signed_out           = "Sesión cerrada",
        -- login dialog
        login_title          = "TaleTrack · Iniciar sesión",
        email_hint           = "tu@email.com",
        cancel               = "Cancelar",
        send_code            = "Enviar código",
        enter_email          = "Por favor introduce tu email",
        enter_code_title     = "Introduce el código",
        code_sent_to         = "Código enviado a {}",
        code_hint            = "000000",
        back                 = "Volver",
        verify               = "Verificar",
        enter_code           = "Por favor introduce el código",
    },
}

local I18n = {}

function I18n.setup()
    local lang = "en"
    local raw
    pcall(function()
        raw = G_reader_settings and G_reader_settings:readSetting("language")
    end)
    if type(raw) == "string" and raw:sub(1, 2) == "es" then
        lang = "es"
    end

    local dict = Strings[lang]

    -- t("key") or t("key", value) — {} in the string is replaced by value.
    local function t(key, value)
        local s = dict[key] or Strings.en[key] or key
        if value ~= nil then
            local rep = tostring(value):gsub("%%", "%%%%")
            s = (s:gsub("{}", rep))
        end
        return s
    end

    return { lang = lang, t = t }
end

return I18n
