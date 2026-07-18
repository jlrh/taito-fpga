/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 2-4-2022 */

module jtopwolf_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire [15:0] oram_dout, pal_dout;
wire [ 1:0] main_dsn;
wire        obj_cs, ram_cs, vram_cs, main_rnw;   // 'sub_cs' ahora es el bus SDRAM del Z80
                                                  // sustituto del C-Chip (lo declara memgen)
wire        scr_cs, pal_cs, sdakn, odakn;
wire [ 2:0] obj_pal;

wire        flip;
wire        sn_rd, sn_we, snd_rstn, mintn;
wire [ 3:0] sn_dout;

// --- DELTA opwolf: C-Chip + light gun ---
wire        cchip_cs, asic_cs, cchip_rstn, gun_latch;
wire [ 7:0] cchip_dout;
wire [ 1:0] motor;
wire [ 8:0] gun_x, gun_y, hdump, vrender;

assign dip_flip = flip;
// work RAM 32 KB (0x100000-0x107fff) | VRAM del PC080SN 64 KB (0xc00000-0xc0ffff)
assign ram_addr = ram_cs ? {3'd0, main_addr[14:1] } : { 2'b10, main_addr[15:1] };
assign ram_we   = xram_cs & ~main_rnw;
assign xram_cs  = ram_cs | vram_cs;
assign ram_dsn  = main_dsn;

opwolf_main u_main(
    .rst        ( rst       ),
    .clk        ( clk       ), // 48 MHz
    .LVBL       ( LVBL      ),

    .main_addr  ( main_addr ),
    .main_dout  ( main_dout ),
    .main_dsn   ( main_dsn  ),
    .main_rnw   ( main_rnw  ),
    .rom_cs     ( main_cs   ),
    .ram_cs     ( ram_cs    ),
    .vram_cs    ( vram_cs   ),
    .obj_cs     ( obj_cs    ),
    .pal_cs     ( pal_cs    ),
    .scr_cs     ( scr_cs    ),

    .obj_pal    ( obj_pal   ),
    .oram_dout  ( oram_dout ),
    .pal_dout   ( pal_dout  ),
    .ram_dout   ( ram_data  ),
    .ram_ok     ( ram_ok    ),
    .rom_data   ( main_data ),
    .rom_ok     ( main_ok   ),

    .odakn      ( odakn     ),
    .sdakn      ( sdakn     ),

    // Sound interface
    .sn_dout    ( sn_dout   ),
    .sn_rd      ( sn_rd     ),
    .sn_we      ( sn_we     ),

    // test board interface
    .snd_rstn   ( snd_rstn  ),
    .mintn      ( mintn     ),

    // C-Chip + pistola (delta opwolf)
    .cchip_cs   ( cchip_cs  ),
    .asic_cs    ( asic_cs   ),
    .cchip_dout ( cchip_dout),
    .cchip_rstn ( cchip_rstn),
    .gun_x      ( gun_x     ),
    .gun_y      ( gun_y     ),
    .gun_latch  ( gun_latch ),
    .motor      ( motor     ),

    .joystick1  ( joystick1 ),
    .joystick2  ( joystick2 ),
    .cab_1p     (cab_1p[1:0]),
    .coin       ( coin[1:0] ),
    .tilt       ( 1'b1      ),   // TILT DESACTIVADO (ver nota en cchip_in1): evita lockups accidentales
    .service    ( service   ),

    .dip_test   ( dip_test  ),
    .dip_pause  ( dip_pause ),
    .dipsw_a    (dipsw[ 7:0]),
    .dipsw_b    (dipsw[15:8])
);

// C-Chip: SUSTITUTO del bootleg (Z80 + ROM de 32 KB = la HLE ya escrita). Ver opwolf_cchip.v
// 4 MHz para el Z80 sustituto del C-Chip (bootleg). clk = clk48 = 53.365 MHz (NO 26.686 = clk24)
// -> 231/3082 = 4.0 MHz. OJO con jtframe_frac_cen: cen[0] es la BASE. Ver GOTCHAS §H7 y memoria
// clk-real-es-clk48-no-26686 (antes 231/1541 daba 8 MHz -> Z80 2x rapido en placa).
wire cchip_cen4, cchip_cen2;
jtframe_frac_cen #(.WC(12)) u_cchipcen(
    .clk  ( clk       ),
    .n    ( 12'd231   ),
    .m    ( 12'd3082  ),
    .cen  ( {cchip_cen2, cchip_cen4} ),
    .cenb (           )
);

// IN0/IN1 = los puertos que en el PCB real lee el C-Chip (NO estan en el bus del 68000).
// Polaridad (opwolf.cpp, INPUT_PORTS opwolf):
//   IN0: bit0 COIN1, bit1 COIN2  -> ACTIVOS A NIVEL ALTO (jtframe los da activos BAJOS -> invertir)
//        bits 2-7 sin uso, ACTIVOS A NIVEL BAJO -> se leen como 1
//   IN1: bit0 BUTTON1(gatillo), bit1 BUTTON2(granada), bit2 SERVICE1, bit3 TILT, bit4 START1
//        todos ACTIVOS A NIVEL BAJO; bits 5-7 sin uso -> 1
wire coin0_raw = ~coin[0];
`ifdef SIMULATION
// DEBUG: repro de mame_inject_gameplay.lua para el bug del GATILLO ("dispara una vez y al soltar
// ya no responde; ni gatillo ni granada"). Secuencia: MONEDA (1 toque limpio) -> START -> DISPARO
// toggling. El gatillo/granada los procesa el codigo de NIVEL de la EPROM (opcodes EQAX/NEAX/... que
// SOLO corren en partida), nunca validado en integrado. Observable: 'CCHIP -> RAM[1005]' (byte crudo
// de botones que el C-Chip pasa al 68000). Si tras el 1er release deja de reflejar el toggle -> bug.
integer sim_fr=0; reg lvbl_lg=0, coin_inj=0, start_inj=0, fire_inj=0, gren_inj=0;
always @(posedge clk) begin
    lvbl_lg <= LVBL;
    if( !LVBL && lvbl_lg ) sim_fr <= sim_fr+1;   // cuenta frames
    // ⚠ TOQUE CORTO de moneda (10 frames): un mantenido largo tripa el "COIN ERROR" del C-Chip (bug
    //   reproducido; MAME acepta 40 frames). En placa 1 toque corto = 1 credito. Objetivo: ENTRAR EN
    //   MISION sin coin error para poder probar el gatillo en el CODIGO DE NIVEL (ahi vive el bug).
    coin_inj  <= (sim_fr>=150 && sim_fr<160) ? 1'b1 : 1'b0;   // moneda: toque corto -> 1 credito
    start_inj <= (sim_fr>=240 && sim_fr<250) ? 1'b1 : 1'b0;   // start -> inicio de mision
    // DISPARO ya en TIROTEO ACTIVO (pasado el banner "作戦開始", ~frame 680): patron MANTENER+SOLTAR,
    //   que es el sintoma EXACTO de placa ("disparas, sueltas, se queda pillado disparando o muerto").
    //   HOLD 40 frames / release 40 frames, repetido. Observable: 'CCHIP -> RAM[1005]' debe alternar
    //   fe<->ff; si se QUEDA PEGADO tras un release -> LATCH CONGELADO = bug reproducido.
    fire_inj  <= (sim_fr>=680 && (sim_fr % 80) < 40) ? 1'b1 : 1'b0;   // 40 ON / 40 OFF (mantener+soltar)
    gren_inj  <= (sim_fr>=700 && (sim_fr % 80) < 40) ? 1'b1 : 1'b0;   // granada, desfasada
end
wire coin0_in = coin0_raw | coin_inj;   // COIN1 activo alto
`else
wire coin0_in = coin0_raw;
wire start_inj = 1'b0, fire_inj = 1'b0, gren_inj = 1'b0;
`endif
wire [7:0] cchip_in0 = { 6'b111111, ~coin[1], coin0_in };
// ⚠ TILT DESACTIVADO (bit3 = 1 = "no tilt", activo bajo). En un setup domestico de MiSTer NO hay
//   interruptor de vuelco/slam: jtframe solo activa tilt desde UNA tecla y Operation Wolf lo ENCLAVA
//   (lockout de entradas hasta reset). Solo puede dar bloqueos accidentales (adaptador de pistola /
//   tecla suelta). Se ata a inactivo. Ver HANDOFF. (El puerto 0x3a0000 tambien: .tilt(1'b1) en u_main.)
// bits activos BAJO (0=pulsado): el inyector de sim los fuerza a 0 en su ventana (start bit4,
//   granada bit1, gatillo bit0). En HW start_inj/fire_inj/gren_inj = 0 -> queda el cableado normal.
wire [7:0] cchip_in1 = { 3'b111, cab_1p[0] & ~start_inj, 1'b1 /*tilt off*/, service,
                         joystick1[5] & ~gren_inj, joystick1[4] & ~fire_inj };

// --- TELEMETRIA de placa del C-Chip para diagnosticar el gatillo pillado (BEAR-VS-WOLF §7).
//     0 en el build del bootleg (no lleva el C-Chip real).
wire [ 7:0] dbg_r1005, dbg_wr1005, dbg_ch1005, dbg_instr;
wire [15:0] dbg_pc;

`ifdef OPWOLF_CCHIP78
// ============================================================================================
// C-CHIP REAL (LLE): uPD78C11 corriendo LAS ROM REALES -> DESBLOQUEA EL SET ORIGINAL 'opwolf'.
// Las dos ROM (interna 4K + EPROM 8K) viven en la BRAM 'cchip' (16K), cargada por PROM desde
// la .mra, en las MISMAS direcciones que ve la CPU: 0x0000 y 0x2000.
// El bus 'sub' (que en el bootleg lleva el Z80 sustituto) aqui NO se usa.
// ============================================================================================
assign sub_addr = 15'd0;
assign sub_cs   = 0;

// 12 MHz (XTAL3 del esquematico). clk = clk48 = 53.365 MHz (NO 26.686 = clk24) -> 899/3998 =
// 12.0007 MHz. (Antes 899/1999 daba 24 MHz -> C-Chip 2x rapido. Ver memoria clk-real-es-clk48-no-26686.)
// ⚠ El cen DEBE quedar por debajo de 1/2 o la BRAM no llega a tiempo y la CPU leeria el
//   OPCODE COMO OPERANDO (ver la nota de LATENCIA en opwolf_cchip78.v). 0.2249 < 0.5 ✔
wire cchip_cen12;
jtframe_frac_cen #(.WC(12)) u_cchipcen12(
    .clk  ( clk       ),
    .n    ( 12'd899   ),
    .m    ( 12'd3998  ),
    .cen  ( { cchip_cen12 } ),
    .cenb (           )
);

opwolf_cchip78 u_cchip(
    .rst        ( rst | ~cchip_rstn ),
    .clk        ( clk        ),
    .cen12      ( cchip_cen12 & dip_pause ),  // PAUSE: congela el C-Chip junto al 68000 (que para con
                                              // HALTn=dip_pause). Si el C-Chip sigue corriendo en pausa
                                              // se desincroniza del 68000 -> handshake roto -> tilt/error.
    .addr       (main_addr[11:1]),
    .din        (main_dout[7:0] ),
    .dout       ( cchip_dout ),
    .cs         ( cchip_cs   ),
    .asic_cs    ( asic_cs    ),
    .rnw        ( main_rnw   ),
    .rom_addr   ( cchip_addr ),
    .rom_data   ( cchip_data ),
    .LVBL       ( LVBL       ),
    .cab_in0    ( cchip_in0  ),
    .cab_in1    ( cchip_in1  ),
    .st_dout    (            ),
    .undef      (            ),
    .dbg_r1005  ( dbg_r1005  ),
    .dbg_wr1005 ( dbg_wr1005 ),
    .dbg_ch1005 ( dbg_ch1005 ),
    .dbg_instr  ( dbg_instr  ),
    .dbg_pc     ( dbg_pc     )
);
`else
// C-Chip SUSTITUTO del bootleg (Z80 + ROM de 32 KB = la HLE que escribieron los bootleggers).
// La EPROM del C-Chip real no se usa por este camino -> se ata el puerto de la BRAM.
assign cchip_addr = 14'd0;

opwolf_cchip u_cchip(
    .rst        ( rst | ~cchip_rstn ),
    .clk        ( clk       ),
    .cen4       ( cchip_cen4 & dip_pause ),   // PAUSE: congela el Z80 sustituto junto al 68000 (idem LLE)
    .addr       (main_addr[11:1]),
    .din        (main_dout[7:0] ),
    .dout       ( cchip_dout),
    .cs         ( cchip_cs  ),
    .rnw        ( main_rnw  ),
    .rom_addr   ( sub_addr  ),
    .rom_cs     ( sub_cs    ),
    .rom_ok     ( sub_ok    ),
    .rom_data   ( sub_data  ),
    .LVBL       ( LVBL      ),
    .cab_in0    ( cchip_in0 ),
    .cab_in1    ( cchip_in1 ),
    .st_dout    (           )
);
assign {dbg_r1005,dbg_wr1005,dbg_ch1005,dbg_instr,dbg_pc} = 48'd0;  // el bootleg no lleva telemetria
`endif

// ============================================================================================
// TELEMETRIA EN PLACA del gatillo (OSD debug_view, seleccionado por debug_bus). El pillado es un
// estado PERSISTENTE -> se leen los contadores CON CALMA tras el pillado. Ver research/BEAR-VS-WOLF.md.
//   Cadena del input:  joystick1 -> cchip_in1 -> [C-Chip lo lee] -> RAM[1005] -> [68000 dispara]
//   ¿Dónde se rompe? Pulsa gatillo varias veces con el disparo pillado y mira qué contador SE MUEVE:
//     cnt_in    sube y cnt_ch1005 NO -> el C-Chip recibe el input pero deja de reflejarlo (bug del core)
//     cnt_in    NO sube               -> el input NO llega al C-Chip (entrega: jtframe/pistola) -> mira joystick1
//     cnt_wr1005 NO sube              -> el C-Chip dejó de correr el código del write (atascado) -> mira dbg_pc
// ============================================================================================
reg [7:0] cnt_in = 8'd0, cchip_in1_l = 8'hff;
always @(posedge clk, posedge rst) begin
    if( rst ) begin cnt_in <= 8'd0; cchip_in1_l <= 8'hff; end
    else begin
        cchip_in1_l <= cchip_in1;
        if( cchip_in1_l != cchip_in1 ) cnt_in <= cnt_in + 8'd1;   // nº de cambios del input al C-Chip
    end
end

reg [7:0] dbg_tele;
always @(*) begin
    case( debug_bus )
        8'h00:   dbg_tele = cchip_in1;              // input CRUDO que entra al C-Chip (b0=gat b1=gra b4=start, act.BAJO)
        8'h01:   dbg_tele = dbg_r1005;              // último byte que el C-Chip SACA al 68000 (debe = cchip_in1)
        8'h02:   dbg_tele = cnt_in;                 // ¿el input LLEGA? (sube al pulsar)
        8'h03:   dbg_tele = dbg_ch1005;             // ¿el C-Chip REFLEJA el cambio? (debe subir con cnt_in)
        8'h04:   dbg_tele = dbg_wr1005;             // ¿corre el código del write? (sube ~cada frame si vivo)
        8'h05:   dbg_tele = joystick1;              // input CRUDO de jtframe (b4=gatillo b5=granada) -> ¿entrega?
        8'h06:   dbg_tele = dbg_instr;              // heartbeat del C-Chip (sube siempre si está vivo)
        8'h07:   dbg_tele = dbg_pc[7:0];            // PC bajo del C-Chip (¿atascado en un bucle?)
        8'h08:   dbg_tele = dbg_pc[15:8];           // PC alto del C-Chip
        8'h09:   dbg_tele = cchip_in0;              // input de monedas al C-Chip
        8'h0a:   dbg_tele = { cchip_rstn, gun_latch, 4'b0, motor };   // estado: b7=reset C-Chip b6=latch pistola b1:0=motor
        default: dbg_tele = 8'hA5;                  // marcador: selección no usada
    endcase
end
assign debug_view = dbg_tele;   // ⚠ sustituye el debug_view del módulo de vídeo (ver instancia u_video)

// Light gun: contadores H/V + latch (modelo del HW real, esquematicos seccion 5)
// Pistola: jtframe (JTFRAME_LIGHTGUN) da la posicion apuntada en coordenadas de PANTALLA.
// Los offsets son los del set opwolfb (ver opwolf_gun.v).
opwolf_gun u_gun(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .latch_en   ( gun_latch ),
    .gun_1p_x   ( gun_1p_x  ),
    .gun_1p_y   ( gun_1p_y  ),
    .gun_x      ( gun_x     ),
    .gun_y      ( gun_y     )
);

opwolf_snd u_sound(
    .rst        ( rst24         ),
    .clk        ( clk24         ), // 24 MHz

    // From main CPU
    .rst48      ( rst           ),
    .clk48      ( clk           ),
    .main_addr  (main_addr[1]   ),
    .main_dout  (main_dout[3:0] ),
    .main_din   ( sn_dout       ),
    .main_rnw   ( main_rnw      ),
    .sn_we      ( sn_we         ),
    .sn_rd      ( sn_rd         ),

    .rom_addr   ( snd_addr      ),
    .rom_cs     ( snd_cs        ),
    .rom_ok     ( snd_ok        ),
    .rom_data   ( snd_data      ),

    // opwolf lleva DOS MSM5205 (rastan solo uno), cada uno con su banco de registros ADPCM.
    // Los dos leen de la MISMA ROM de muestras de 512 KB (b20-08.21): en mem.yaml pcm0 y pcm1
    // comparten PCM_OFFSET.
    .pcm0_addr  ( pcm0_addr     ),
    .pcm0_cs    ( pcm0_cs       ),
    .pcm0_ok    ( pcm0_ok       ),
    .pcm0_data  ( pcm0_data     ),

    .pcm1_addr  ( pcm1_addr     ),
    .pcm1_cs    ( pcm1_cs       ),
    .pcm1_ok    ( pcm1_ok       ),
    .pcm1_data  ( pcm1_data     ),

    .fm_l       ( fm_l          ),
    .fm_r       ( fm_r          ),
    .pcm0       ( pcm0          ),
    .pcm1       ( pcm1          )
);

opwolf_video u_video(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    .HS         ( HS        ),
    .VS         ( VS        ),
    .LHBL       ( LHBL      ),
    .LVBL       ( LVBL      ),
    .flip       ( flip      ),
    .hdump      ( hdump     ),
    .vrender    ( vrender   ),
    .obj_pal    ( obj_pal   ),

    .main_addr  ( main_addr ),
    .main_dout  ( main_dout ),
    .oram_dout  ( oram_dout ),
    .pal_dout   ( pal_dout  ),
    .main_dsn   ( main_dsn  ),
    .main_rnw   ( main_rnw  ),
    .scr_cs     ( scr_cs    ),
    .pal_cs     ( pal_cs    ),
    .obj_cs     ( obj_cs    ),
    .sdakn      ( sdakn     ),
    .odakn      ( odakn     ),

    .ram0_addr  ( scr0ram_addr ),
    .ram0_data  ( scr0ram_data ),
    .ram0_ok    ( scr0ram_ok   ),
    .ram0_cs    ( scr0ram_cs   ),

    .rom0_addr  ( scr0rom_addr ),
    .rom0_data  ( scr0rom_data ),
    .rom0_cs    ( scr0rom_cs   ),
    .rom0_ok    ( scr0rom_ok   ),

    .ram1_addr  ( scr1ram_addr ),
    .ram1_data  ( scr1ram_data ),
    .ram1_ok    ( scr1ram_ok   ),
    .ram1_cs    ( scr1ram_cs   ),

    .rom1_addr  ( scr1rom_addr ),
    .rom1_data  ( scr1rom_data ),
    .rom1_cs    ( scr1rom_cs   ),
    .rom1_ok    ( scr1rom_ok   ),

    .orom_addr  ( orom_addr    ),
    .orom_data  ( orom_data    ),
    .orom_cs    ( orom_cs      ),
    .orom_ok    ( orom_ok      ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    // Debug
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( ioctl_addr[10:0]),
    .ioctl_din  ( ioctl_din ),
    .debug_view (           )   // ⚠ debug_view lo dirige la TELEMETRIA del gatillo (assign arriba), no el vídeo
);

endmodule
