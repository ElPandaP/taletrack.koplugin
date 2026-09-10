# TaleTrack — Plugin de KOReader

Plugin en Lua para [KOReader](https://github.com/koreader/koreader) que registra en tu cuenta de
TaleTrack lo que lees: el progreso de lectura mientras avanzas y el libro como terminado al
acabarlo. Vive como submódulo git independiente
(`https://github.com/ElPandaP/taletrack.koplugin`), con su propio repo/historial.

## Instalación

Copia (o clona) esta carpeta dentro de `koreader/plugins/` en tu dispositivo, con el nombre
`taletrack.koplugin` — KOReader detecta los plugins por el sufijo `.koplugin` del nombre de carpeta.

## Estructura

```
_meta.lua          # nombre/descripción/versión del plugin, la lee KOReader
main.lua            # punto de entrada: eventos del lector, hook de "estado del libro", menú
api.lua             # comunicación HTTP con el backend (login OTP, refresh, trackear libro)
sync.lua            # cola offline de sincronización de progreso (persistida)
login_dialog.lua    # diálogo de login en dos pasos: email → código de 6 dígitos
i18n.lua            # textos ES/EN según el idioma configurado en KOReader
logo.png            # icono del plugin
```

## Cómo trackea

**Progreso mientras lees.** `main.lua` escucha `onPageUpdate` y, como mucho una vez cada
2 minutos mientras pasas páginas, calcula el porcentaje de lectura
(`ReaderPaging`/`ReaderRolling:getLastPercent()`) y lo encola. También encola al llegar al
final del libro (`onEndOfBook` → 100), al cerrar el documento y al suspender.

**Libro terminado.** Sigue parcheando `BookStatusWidget.init` para enterarse cuando marcas un
libro como "completado" (desde el lector o desde el explorador/historial); eso encola progreso
100 y muestra el único aviso que queda ("registrado como finalizado"). Ya no hay prompt al
cerrar en la última página.

**Cola offline (`sync.lua`).** Cada entrada es un libro con su último progreso; encolar de
nuevo el mismo libro **sustituye** la entrada (nos quedamos con el porcentaje más alto), así
que 8 actualizaciones seguidas se resuelven con un solo `POST`. La cola se persiste en
`taletrack_queue.lua` y se vacía cuando hay red: al abrir el lector, al reconectar
(`onNetworkConnected`), al reanudar y tras cada envío. El backend es idempotente y el progreso
solo sube (`Math.Max`), así que reenviar es inofensivo. Si no hay conexión, `flush` no hace
nada y la cola espera.

El título sale de los metadatos del documento (o `"Desconocido"` si no hay); la clave de
deduplicación de la cola es el `partial_md5_checksum` del documento, o el título si no está.

## Auth

Login por **código OTP** (`login_dialog.lua`, dos pasos): pides el email
(`TaleTrack:requestCode` → `Api.requestCode` → `POST /api/auth/request-code`), introduces el código de
6 dígitos que llega por email (`TaleTrack:verifyCode` → `Api.verifyCode` → `POST /api/auth/verify-code`).
Se guardan **el access token y el refresh token** en `LuaSettings`
(`DataStorage:getSettingsDir()/TaleTrack.lua`).

El access token dura ~1 h; no se calcula la caducidad en local (el reloj de los e-readers no es
fiable). Cuando un `POST` de progreso devuelve **401**, `sync.lua` canjea el refresh token por
un par nuevo (`POST /api/auth/refresh`, que rota el refresh token — se guarda el nuevo) y
reintenta. Solo si el refresh también falla se borran los tokens y se pide iniciar sesión de
nuevo (un único aviso, no uno por cada elemento de la cola).

## Servidor

`api.lua` tiene `SERVER_URL` **hardcodeado** a `http://143.47.54.63` (la VM de producción) — para
apuntar a un backend local hay que editar esa constante a mano y volver a copiar el plugin al
dispositivo. Detecta http/https automáticamente y usa `socket.http` o `ssl.https` según toque
(`ssl.https` no está disponible en todos los dispositivos). Los tiempos de espera se acortan con
`socketutil` para que una red caída falle en segundos en vez de colgarse.
