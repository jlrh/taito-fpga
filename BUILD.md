# Building the core (reproducible) — Operation Wolf

🇬🇧 English (below) · [🇪🇸 Español](#compilar-el-core-reproducible--operation-wolf)

Steps to rebuild the `.rbf` from scratch. Unlike some coprocessor cores, **no patch is required**: the
Taito C-Chip firmware and the game ROMs are loaded at **runtime** from the `.mra`, so the bitstream is
distributable as-is. Tested for MiSTer.

## Requirements
- A [**jtcores**](https://github.com/jotego/jtcores) checkout (brings jtframe + jt51 + jt5205 as modules)
  and its toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (the version your MiSTer board needs).
- Your Operation Wolf **ROMs** (not included), **including the C-Chip firmware** `cchip_upd78c11.bin` —
  see [`README.md`](README.md).

## Steps

1. **Place the core** inside jtcores:
   ```
   cp -r cores/opwolf  <jtcores>/cores/opwolf
   ```

2. **Build** (generate + compile):
   ```
   cd <jtcores> && source setprj.sh
   jtcore opwolf -mister -c
   ```
   This generates `<jtcores>/cores/opwolf/mister/` (Quartus project + the memgen GAMETOP
   `jtopwolf_game_sdram.v`) and compiles it. The result is the `.rbf` under `mister/output_files/`.

   > The core is **CLK24, single clock domain** (SDRAM in the same domain), so there is no clk48↔clk96
   > crossing and **no `.sdc` is required** — the fitter closes timing with positive slack.

## The C-Chip

The **original set (`opwolf`)** uses the real Taito C-Chip, a **uPD78C11** microcontroller, recreated
here as an LLE CPU core (`upd7810`, written from scratch — there is no uPD78C11 core in jtframe). Its
internal firmware (`cchip_upd78c11.bin`) and the external C-Chip EPROM (`b20-18.73`) are declared as ROM
regions in the `.mra`, so they enter the download stream and are **loaded at runtime** — **not baked**
into the bitstream.

## Legal / distribution
- This repo's **code** is GPLv3 and contains no ROMs or firmware.
- The **`.rbf` in [`releases/`](releases/)** was built with these steps: neither the game ROMs nor the
  C-Chip firmware are inside → it is **distributable**. The **ROMs and the C-Chip firmware** are provided
  by each user.

---

# Compilar el core (reproducible) — Operation Wolf

🇪🇸 Español · [🇬🇧 English ↑](#building-the-core-reproducible--operation-wolf)

Pasos para reconstruir el `.rbf` desde cero. A diferencia de algunos cores con coprocesador, **no hace
falta ningún parche**: el firmware del C-Chip de Taito y las ROMs del juego se cargan en **runtime** desde
el `.mra`, así que el bitstream es distribuible tal cual. Probado para MiSTer.

## Requisitos
- Un checkout de [**jtcores**](https://github.com/jotego/jtcores) (trae jtframe + jt51 + jt5205 como
  módulos) y su toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (la versión que pida tu placa MiSTer).
- Tus **ROMs** de Operation Wolf (no se incluyen), **incluido el firmware del C-Chip**
  `cchip_upd78c11.bin` — ver [`README.md`](README.md).

## Pasos

1. **Coloca el core** dentro de jtcores:
   ```
   cp -r cores/opwolf  <jtcores>/cores/opwolf
   ```

2. **Compila** (genera + compila):
   ```
   cd <jtcores> && source setprj.sh
   jtcore opwolf -mister -c
   ```
   Esto genera `<jtcores>/cores/opwolf/mister/` (proyecto Quartus + el GAMETOP de memgen
   `jtopwolf_game_sdram.v`) y lo compila. El resultado es el `.rbf` en `mister/output_files/`.

   > El core es **CLK24, un solo dominio de reloj** (la SDRAM va en el mismo dominio), así que no hay
   > cruce clk48↔clk96 y **no hace falta `.sdc`** — el fitter cierra timing con slack positivo.

## El C-Chip

El **set original (`opwolf`)** usa el C-Chip real de Taito, un microcontrolador **uPD78C11**, recreado
aquí como un core de CPU por LLE (`upd7810`, escrito desde cero — no existe un core de uPD78C11 en
jtframe). Su firmware interno (`cchip_upd78c11.bin`) y la EPROM externa del C-Chip (`b20-18.73`) se
declaran como regiones ROM en el `.mra`, de modo que entran en el stream de descarga y se **cargan en
runtime** — **no van horneados** en el bitstream.

## Legalidad / distribución
- El **código** de este repo es GPLv3 y no contiene ROMs ni firmware.
- El **`.rbf` de [`releases/`](releases/)** se compiló con estos pasos: ni las ROMs del juego ni el
  firmware del C-Chip van dentro → es **distribuible**. Las **ROMs y el firmware del C-Chip** los aporta
  cada usuario.
