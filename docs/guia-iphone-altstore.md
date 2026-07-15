# Guía definitiva: CBUM en tu iPhone con AltStore (sin pagar los $99)

Objetivo final: la app corriendo en tu iPhone y **re-firmándose sola** cada semana vía AltStore. Asume que el branch `system` (ios/) ya está mergeado a main.

Requisitos: Mac con macOS 11+, Xcode 15+, iPhone con iOS 17+, cable, y tu Apple ID. Tiempo: ~45 min la primera vez.

---

## Parte A — Xcode (una sola vez)

1. **Instala Xcode** desde el App Store. Ábrelo una vez y deja que instale el "iOS platform" cuando lo pida.
2. **Agrega tu Apple ID**: Xcode → Settings (⌘,) → Accounts → `+` → Apple ID. Al agregarlo aparece tu **Personal Team** — esa es la cuenta gratuita de desarrollo.
3. **Abre el proyecto**: doble clic a `ios/CBUM.xcodeproj`.
4. **Firma**: en el navegador izquierdo clic al proyecto **CBUM** (ícono azul) → target **CBUM** → pestaña **Signing & Capabilities** → marca *Automatically manage signing* → Team: tu **Personal Team**. Si el bundle id `com.mackley.cbum` diera conflicto, cámbialo a algo único (ej. `com.mackley.cbum2`).
5. **Compila y corre los tests** (paso crítico — nadie ha compilado este código aún):
   - `⌘B` (build). Si hay errores, copia el texto completo y pégamelo en el chat: yo corrijo el código.
   - `⌘U` (tests). `FormulasKitTests` debe pasar 100% — valida las fórmulas de precisión.
6. **Prueba en simulador**: arriba elige un iPhone del simulador como destino → `⌘R`. Explora la app con el mock (datos semilla). HealthKit funciona en simulador: puedes agregar un peso en la app Salud del simulador y verificar que CBUM lo lea.
7. **Prepara tu iPhone físico** (para AltStore y para debugging):
   - Conéctalo por cable, desbloquéalo, "Confiar en este computador".
   - Activa **Developer Mode**: Ajustes → Privacidad y seguridad → Modo de desarrollador → ON (reinicia el iPhone).
   - En el Mac: Finder → tu iPhone en la barra lateral → marca **"Mostrar este iPhone cuando esté en WiFi"**.

## Parte B — Generar el .ipa

Cada vez que cambies código y quieras actualizar el teléfono:

```bash
./scripts/make-ipa.sh
```

Produce `build/CBUM.ipa`. El script compila Release firmado con tu Personal Team (usa la sesión de Xcode) y lo empaqueta. Si la firma por línea de comandos fallara, corre `./scripts/make-ipa.sh --unsigned` (AltStore re-firma de todas formas).

> Primera vez sin script: en Xcode elige destino "Any iOS Device (arm64)" → `⌘B`, y el script hace el resto igual.

## Parte C — AltServer + AltStore (una sola vez)

1. **Descarga AltServer** de [altstore.io](https://altstore.io) (versión "AltStore Classic" para macOS), copia `AltServer.app` a `/Applications` y ábrelo. Aparece como ícono en la **barra de menú** (no tiene ventana).
2. **Contraseña específica de app** (recomendado, no le des tu contraseña real): [appleid.apple.com](https://appleid.apple.com) → Iniciar sesión → App-Specific Passwords → genera una llamada "altstore".
3. **Instala AltStore en el iPhone**: iPhone conectado por cable y desbloqueado → clic al ícono de AltServer en la barra de menú → **Install AltStore** → tu iPhone → ingresa Apple ID + la contraseña específica de app.
4. **Confía en el certificado** en el iPhone: Ajustes → General → VPN y gestión de dispositivos → tu Apple ID → Confiar → Permitir.
5. Abre la app **AltStore** en el iPhone y verifica que carga (pestaña My Apps).

## Parte D — Instalar CBUM vía AltStore

1. Pásale el `.ipa` al iPhone: AirDrop `build/CBUM.ipa` a tu iPhone (o guárdalo en iCloud Drive).
2. En el iPhone: abre **AltStore → My Apps → `+`** (arriba a la izquierda) → elige `CBUM.ipa` → ingresa credenciales si las pide.
3. CBUM aparece en el home screen. Ábrela y **verifica HealthKit**: debe pedirte permisos de Salud al arrancar. ⚠️ Si NO los pide o falla al guardar en Salud, el re-firmado perdió el entitlement — avísame y usamos el plan B (instalar directo por Xcode, ritual manual).

## Parte E — El auto-refresh (el punto de todo esto)

Para que AltStore re-firme CBUM solo, sin que toques nada:

1. **AltServer siempre corriendo en el Mac**: System Settings → General → Login Items → agrega AltServer. Queda en la barra de menú al iniciar sesión.
2. En el iPhone: Ajustes → General → **Background App Refresh** → ON para AltStore, y notificaciones de AltStore ON (te avisa si un refresh falla).
3. Condición de funcionamiento: iPhone y Mac **en la misma WiFi** regularmente (tu casa). AltStore refresca en background cuando detecta a AltServer.
4. Red de seguridad: abre AltStore → My Apps de vez en cuando; si ves pocos días restantes, botón **Refresh All** (con el Mac en la misma red).

**Si la app expiró** (7 días sin ver al Mac): no se pierde nada — los datos están en SwiftData/tu backend. Refresh All desde AltStore (o re-sideload) y todo vuelve.

## Parte F — Flujo cuando cambias código

```
editar código → ⌘U en Xcode (tests) → ./scripts/make-ipa.sh → AirDrop → AltStore My Apps + → reemplaza CBUM
```

Los datos sobreviven a la actualización (mismo bundle id = mismo contenedor).

---

## Límites y troubleshooting

- **3 apps máximo** sideloaded con cuenta gratuita: AltStore + CBUM = 2 ocupadas, te queda 1.
- **10 App IDs por semana** por cuenta gratuita — no es problema con una sola app.
- AltServer pide login de nuevo de vez en cuando (sesión Apple expira): normal, re-ingresa la contraseña específica de app.
- "Developer Mode required" al abrir → paso A7.
- El refresh falla siempre → verifica misma WiFi, AltServer corriendo, y que el Mac no esté durmiendo (System Settings → deshabilita "Poner los discos en reposo" o usa `caffeinate`).
- **Plan B siempre disponible**: iPhone por cable → Run en Xcode (el ritual manual de 1 min).
- **Plan definitivo**: si en un mes usas CBUM a diario, los $99/año eliminan todo esto (firma anual + TestFlight).
