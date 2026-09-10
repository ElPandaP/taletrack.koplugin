# TaleTrack — Plugin de KOReader

Plugin en Lua para [KOReader](https://github.com/koreader/koreader) que registra en tu cuenta de
TaleTrack los libros que terminas de leer. Vive como submódulo git independiente
(`https://github.com/ElPandaP/taletrack.koplugin`), con su propio repo/historial.

## Instalación

Copia (o clona) esta carpeta dentro de `koreader/plugins/` en tu dispositivo, con el nombre
`taletrack.koplugin` — KOReader detecta los plugins por el sufijo `.koplugin` del nombre de carpeta.

## Estructura

```
_meta.lua          # nombre/descripción/versión del plugin, la lee KOReader
main.lua            # punto de entrada: hookea el widget de "estado del libro" y el menú
api.lua             # toda la comunicación HTTP con el backend (login OTP, trackear libro)
login_dialog.lua    # diálogo de login en dos pasos: email → código de 6 dígitos
logo.png            # icono del plugin
```

## Cómo trackea

`main.lua` parchea `BookStatusWidget.init` para enterarse cada vez que marcas un libro como
"completado" (desde el lector o desde el explorador de archivos/historial), y además pregunta si
quieres registrarlo cuando cierras un documento estando en la última página
(`TaleTrack:onCloseDocument`). En ambos casos llama a `syncBook(title, pages, doc_settings)`, que
postea a `POST /api/tracking/books` con `Progress = 100` y guarda una marca
(`doc_settings:saveSetting("TaleTrack_synced", true)`) para no volver a enviarlo.

El título sale de los metadatos del documento (o `"Desconocido"` si no hay), y las páginas de
`doc_pages` / `number_of_pages` en los settings del propio documento.

## Auth

Login por **código OTP** (`login_dialog.lua`, dos pasos): pides el email
(`TaleTrack:requestCode` → `Api.requestCode` → `POST /api/auth/request-code`), introduces el código de
6 dígitos que llega por email (`TaleTrack:verifyCode` → `Api.verifyCode` → `POST /api/auth/verify-code`),
y el JWT que devuelve se guarda en `LuaSettings` (`DataStorage:getSettingsDir()/TaleTrack.lua`) sin
fecha de caducidad gestionada — si el token expira, el siguiente intento de trackear falla con 401 y el
plugin lo borra y pide iniciar sesión de nuevo (no hay refresh token aquí, a diferencia del
frontend/extensión — la API devuelve uno, pero el plugin no lo guarda ni lo usa).

## Servidor

`api.lua` tiene `SERVER_URL` **hardcodeado** a `http://143.47.54.63` (la VM de producción) — para
apuntar a un backend local hay que editar esa constante a mano y volver a copiar el plugin al
dispositivo. Detecta http/https automáticamente y usa `socket.http` o `ssl.https` según toque
(`ssl.https` no está disponible en todos los dispositivos).
