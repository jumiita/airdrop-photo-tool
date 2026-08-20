# AirDrop Photo Tool

Una app sencilla para macOS que convierte fotos HEIC a JPG y ayuda a encontrar fotos duplicadas.

Convierte automáticamente fotos `.HEIC` recibidas por AirDrop en el Mac.

## Descargar

1. Descarga el `.zip` de la [ultima release](https://github.com/jumiita/airdrop-photo-tool/releases/latest).
2. Descomprime `AirDrop HEIC Converter Status.app`.
3. Mueve la app a `Aplicaciones`.
4. Abrela con doble clic.

Si macOS avisa de que la app viene de internet, abre `Ajustes del Sistema > Privacidad y seguridad` y pulsa `Abrir igualmente`.

## Funciones

La app tiene dos pestanas:

- `Convertir HEIC`: permite elegir Descargas, Pictures u otra carpeta, muestra si el servicio esta funcionando, cuantas fotos `.HEIC` quedan por convertir, permite arrancarlo/pararlo y abre la carpeta elegida.
- `Duplicadas`: busca fotos iguales o visualmente parecidas en Descargas, Pictures u otra carpeta, muestra previsualizacion, tamano y espacio que ganarias moviendo duplicadas a la Papelera.

## Convertidor HEIC

- Vigila `~/Downloads`, que es donde macOS guarda lo recibido por AirDrop.
- Convierte `IMG_1895.HEIC` en `IMG_1895.JPG`.
- Te pregunta por lote si quieres borrar los `.HEIC` originales cuando la conversion ha ido bien.
- Muestra notificaciones de macOS al arrancar y al convertir fotos.

## Desarrollo

Compilar la app:

```bash
./build_app.sh
```

Crear un zip para release:

```bash
./make_release.sh 1.0.0
```

Instalar o reiniciar el servicio de conversion:

```bash
./install.sh
```

## Cambiar a PNG

```bash
AIRDROP_OUTPUT_FORMAT=png ./install.sh
```

## Borrar el HEIC tras convertir

Por defecto te lo pregunta por lote. Si quieres que lo borre siempre sin preguntar:

```bash
AIRDROP_DELETE_ORIGINAL=true ./install.sh
```

También puedes combinarlo:

```bash
AIRDROP_OUTPUT_FORMAT=png AIRDROP_DELETE_ORIGINAL=true ./install.sh
```

## Ver logs

```bash
tail -f ~/Library/Logs/airdrop-heic-converter/watcher.log
```

## Desinstalar

```bash
./uninstall.sh
```

## Seguridad

- Las duplicadas se mueven a la Papelera, no se borran permanentemente.
- Los HEIC originales solo se eliminan si el usuario confirma.
- La app usa herramientas incluidas en macOS: SwiftUI, `sips` y `launchctl`.
