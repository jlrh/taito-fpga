# taito-fpga

🇬🇧 English (below) · [🇪🇸 Español](#español)

FPGA recreations of **Taito** arcade boards, built on the **JTFRAME** framework (GPLv3). MiSTer target.

## Cores

### Operation Wolf (Taito, 1987)
On-rails light-gun shooter. Hardware: **MC68000 @8 MHz** + **Z80** sound CPU + **Taito C-Chip**
(a **uPD78C11** microcontroller, protection) + **YM2151** + **2×MSM5205** (ADPCM) + Taito PC060/PC080
video + light gun.

**Status: playable on MiSTer** — the **original set** (`opwolf`) is unlocked because the C-Chip is
recreated as a **low-level emulation (LLE)** CPU core, `upd7810`, **written from scratch** (there is no
uPD78C11 core in jtframe). Boot, video, sprites, background, audio (YM2151 + dual ADPCM) and the light
gun all run on hardware.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: the C-Chip firmware
(`cchip_upd78c11.bin`) and the game ROMs are loaded at **runtime** from the `.mra`, **none is baked into
the bitstream**. Or build from source (`cores/opwolf/`) — no patch is required. See [`BUILD.md`](BUILD.md).

> ℹ️ Naming: the core's own modules drop the `jt` prefix (`opwolf_*`, `upd7810`); only the GAMETOP
> (`jtopwolf_game`) keeps `jt`, because memgen imposes it.

## Build

This repo contains **only the core code** (`cores/opwolf/`). The framework and third-party cores
(jtframe, jt51, jt5205) are **not included** — jtframe provides them. Quick version:

1. Clone [jtcores](https://github.com/jotego/jtcores) (brings jtframe + modules).
2. Copy this repo's `cores/opwolf/` into your jtcores checkout.
3. Build: `jtcore opwolf -mister -c`.

📋 **Step-by-step in [`BUILD.md`](BUILD.md).**

Core layout:
```
cores/opwolf/
├── hdl/   Core Verilog (opwolf_* modules + upd7810 C-Chip LLE + jtopwolf_game GAMETOP)
├── cfg/   macros.def, mem.yaml, files.yaml, msg, reg.yaml, mame2mra.toml
└── mra/   .mra definition (how to assemble the ROMs)
```

## ROMs

**Not included** (copyrighted material). Everyone provides the original ROMs of their own board,
**including the C-Chip firmware** (`cchip_upd78c11.bin`). The `.mra` describes how to assemble them; it
loads the C-Chip firmware at runtime, so the `.rbf` carries no copyrighted data.

## Credits

- **JTFRAME**, **jt51**, **jt5205** — the GPLv3 frameworks this core is built on
- **MAME** — hardware reference (`opwolf.cpp` driver, C-Chip research)

## Acknowledgements

- To **Sorgelig** and the whole **MiSTer FPGA** project and community.
- To the **MAME community**, for the preservation and reverse-engineering work without which this core
  would not be possible.
- And to **Anthropic**, for **Claude**.

## License

**GPLv3** (see [`LICENSE`](LICENSE)) — required by the JTFRAME / jt51 / jt5205 dependencies; their
copyright notices are preserved in the sources.

---

## Español

🇪🇸 Español · [🇬🇧 English ↑](#taito-fpga)

Recreaciones en FPGA de placas arcade de **Taito**, construidas sobre el framework **JTFRAME** (GPLv3).
Objetivo MiSTer.

## Cores

### Operation Wolf (Taito, 1987)
Shooter sobre raíles con pistola de luz. Hardware: **MC68000 @8 MHz** + CPU de sonido **Z80** + **C-Chip
de Taito** (un microcontrolador **uPD78C11**, protección) + **YM2151** + **2×MSM5205** (ADPCM) + vídeo
Taito PC060/PC080 + pistola de luz.

**Estado: jugable en MiSTer** — el **set original** (`opwolf`) queda desbloqueado porque el C-Chip se
recrea como un core de CPU por **emulación de bajo nivel (LLE)**, `upd7810`, **escrito desde cero** (no
existe un core de uPD78C11 en jtframe). Arranque, vídeo, sprites, fondo, audio (YM2151 + doble ADPCM) y
la pistola de luz funcionan en hardware.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: el firmware del C-Chip
(`cchip_upd78c11.bin`) y las ROMs del juego se cargan en **runtime** desde el `.mra`, **nada va horneado
en el bitstream**. O compila desde fuente (`cores/opwolf/`) — no hace falta ningún parche. Ver
[`BUILD.md`](BUILD.md).

> ℹ️ Nomenclatura: los módulos propios del core van **sin** el prefijo `jt` (`opwolf_*`, `upd7810`); solo
> el GAMETOP (`jtopwolf_game`) conserva `jt`, porque memgen lo impone.

## Construir

Este repo contiene **solo el código del core** (`cores/opwolf/`). El framework y los cores de terceros
(jtframe, jt51, jt5205) **no se incluyen** — los aporta jtframe. Versión rápida:

1. Clona [jtcores](https://github.com/jotego/jtcores) (trae jtframe + módulos).
2. Copia `cores/opwolf/` de este repo dentro de tu checkout de jtcores.
3. Compila: `jtcore opwolf -mister -c`.

📋 **Pasos detallados en [`BUILD.md`](BUILD.md).**

Estructura del core:
```
cores/opwolf/
├── hdl/   Verilog del core (módulos opwolf_* + C-Chip LLE upd7810 + GAMETOP jtopwolf_game)
├── cfg/   macros.def, mem.yaml, files.yaml, msg, reg.yaml, mame2mra.toml
└── mra/   definición .mra (cómo ensamblar las ROMs)
```

## ROMs

**No se incluyen** (material con copyright). Cada cual aporta las ROMs originales de su placa, **incluido
el firmware del C-Chip** (`cchip_upd78c11.bin`). El `.mra` describe cómo ensamblarlas; carga el firmware
del C-Chip en runtime, así que el `.rbf` no lleva ningún dato con copyright.

## Créditos

- **JTFRAME**, **jt51**, **jt5205** — los frameworks GPLv3 sobre los que se construye este core
- **MAME** — referencia de hardware (driver `opwolf.cpp`, investigación del C-Chip)

## Agradecimientos

- A **Sorgelig** y todo el proyecto y comunidad **MiSTer FPGA**.
- A la **comunidad MAME**, por el trabajo de preservación e ingeniería inversa sin el cual este core no
  sería posible.
- Y a **Anthropic**, por **Claude**.

## Licencia

**GPLv3** (ver [`LICENSE`](LICENSE)) — obligado por las dependencias JTFRAME / jt51 / jt5205; sus avisos de
copyright se conservan en las fuentes.
