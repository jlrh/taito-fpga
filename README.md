# taito-fpga

Taito arcade cores for **MiSTer**. · Cores arcade de **Taito** para **MiSTer**.

<!-- MOSAICO:AUTO -->

## Horizontal

<table>
<tr>
<td align="center" width="33%"><a href="DETAILS.md#operation-wolf-taito-1987"><img src="docs/screens/opwolf.png" alt="Operation Wolf"></a><br><b>Operation Wolf</b> · 1987</td>
</tr>
</table>

<!-- /MOSAICO:AUTO -->

<!-- INSTALAR:AUTO -->

## How to install the Taito cores on your MiSTer FPGA

Two options:

1. **Download and copy them yourself.** The `.rbf` cores are in [`releases/`](releases/) and go to `_Arcade/cores/` on
   the SD card; the `.mra` files are in `cores/<core>/mra/` and go to `_Arcade/`.
2. **Let the MiSTer Downloader do it.** Add the [jlrh-misterfpga-db](https://github.com/jlrh/jlrh-misterfpga-db)
   database to `downloader.ini` (root of the SD card) and run `Scripts → update`. It installs these cores **and the
   rest of jlrh's arcade cores** (Konami, Gaelco, Seibu, Inder…), and keeps them all up to date.

```ini
[jlrh/jlrh-misterfpga-db]
db_url = https://raw.githubusercontent.com/jlrh/jlrh-misterfpga-db/db/db.json.zip
```

**ROMs are not included.** Bring your own MAME romsets (merged, MAME 0.288) into `games/mame/`. The exact set each core
expects is in [`ROMS.md`](https://github.com/jlrh/jlrh-misterfpga-db/blob/main/ROMS.md).

**More:** build instructions in [`BUILD.md`](BUILD.md); hardware, status, controls and credits of each core in
[`DETAILS.md`](DETAILS.md). Screenshots taken from MAME.

Built on the GPLv3 **JTFRAME** framework. Independent project — **not** an official jotego core. License: GPLv3
([`LICENSE`](LICENSE)).

## Cómo instalar los cores de Taito en tu MiSTer FPGA

Dos opciones:

1. **Descargarlos y copiarlos tú.** Los `.rbf` están en [`releases/`](releases/) y van a `_Arcade/cores/` en la SD;
   los `.mra` están en `cores/<core>/mra/` y van a `_Arcade/`.
2. **Que lo haga el MiSTer Downloader.** Añade la base de datos
   [jlrh-misterfpga-db](https://github.com/jlrh/jlrh-misterfpga-db) a `downloader.ini` (en la raíz de la SD) y ejecuta
   `Scripts → update`. Instala estos cores **y el resto de cores arcade de jlrh** (Konami, Gaelco, Seibu, Inder…), y los
   mantiene todos al día.

```ini
[jlrh/jlrh-misterfpga-db]
db_url = https://raw.githubusercontent.com/jlrh/jlrh-misterfpga-db/db/db.json.zip
```

**Las ROMs no se incluyen.** Pon tus propios romsets de MAME (merged, MAME 0.288) en `games/mame/`. El set exacto que
espera cada core está en [`ROMS.md`](https://github.com/jlrh/jlrh-misterfpga-db/blob/main/ROMS.md).

**Más:** cómo compilar, en [`BUILD.md`](BUILD.md); hardware, estado, controles y créditos de cada core, en
[`DETAILS.md`](DETAILS.md). Capturas tomadas de MAME.

Hechos sobre el framework **JTFRAME** (GPLv3). Proyecto independiente — **no** es un core oficial de jotego. Licencia:
GPLv3 ([`LICENSE`](LICENSE)).

<!-- /INSTALAR:AUTO -->
