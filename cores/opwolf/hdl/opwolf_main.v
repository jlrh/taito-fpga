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
    Date: 3-4-2022 */

/* PAL equations

/o12 = i1 & /i2 & /i3 & /i4 & /i5 & /i6 & /i7 & /i8 & /i11
/ROM0 = ~&FC & A[23:17]==000'0000 & ~AS

/o13 = i1 & /i2 & /i3 & /i4 & /i5 & /i6 & /i7 & i8 & /i11
/ROM1 = ~&FC & A[23:17]==000'0001 & ~AS

/o14 = i1 & /i2 & /i3 & /i4 & /i5 & /i6 & i7 & /i8 & /i11
/ROM2 = ~&FC & A[23:17]==000'0010 & ~AS

/o15 = i1 & i2 & i3 & /i4 & /i5 & /i11
/scn = ~&FC & A[23:20]=='b1100 & ~AS

/o16 = i1 & i2 & i3 & /i4 & i5 & /i11
/obj = ~&FC & A[23:20]=='b1101 & ~AS

/o17 = i1 & /i2 & /i3 & i4 & i5 & /i11
/io  = ~&FC & A[23:20]=='b0011 & ~ASn

/o18 = i1 & /i2 & /i3 & /i11
/dtackn = ~&FC & A[23:22]==0 & ~ASn - Dtack for non video access

/o19 = i1 & i2 & /i3 & /i4 & /i5 & /i11
/ext = &~FC & A[23:22]=='b1001 & ~ASn - seems to be a test port

From Taito-B04-10.jed

/o15 = /i1 & /i2 & i3 & /i4 & /i5 & /i6 & /i7 & /i8 & /i9 & i13
/CLWE = A[23:18]=='b001000 && ~LDS && ~UDS && ~RnW & ~&FC

/o16 = /i1 & /i2 & i3 & /i4 & /i5 & /i6 & /i11 & i13
/CLCS = A[23:18]=='b001000 & ~ASn & ~&FC

/o17 = /i1 & /i2 & /i3 & i4 & /i5 & /i6 & /i8 & /i11 & i13
/WURAM = A[23:18]=='b000100 & ~AS & ~UDS & ~&FC

/o18 = /i1 & /i2 & /i3 & i4 & /i5 & /i6 & /i7 & /i11 & i13
/WLRAM = A[23:18]=='b000100 & ~AS & ~LDS & ~&FC

/o19 = i1 & /i2 & /i3 & /i4 & /i11 & i13
/SUBCS = A[23:20]=='b1000 & ~LDS & ~&FC

From Taito-B04-11.jed

/o14 = /i1 & i2 & /i3 & i4 & /i5 & i6
/irq_clear = &FC & RnW & ~AS & A[3:1]=='b101

/o16 = /i1 & i2 & /i3 & i4 & /i5 & i6
/vpa = &FC & RnW & ~AS & A[3:1]=='b101

/o17 = /i8
/ipl2 = ~irqn

/o19 = /i8
/ipl0 = ~irqn

Note that /i9 (subint) is not connected


*/

module opwolf_main(
    input                rst,
    input                clk, // 48 MHz
    input                LVBL,

    output        [18:1] main_addr,
    output        [ 1:0] main_dsn,
    output        [15:0] main_dout,
    output               main_rnw,
    output reg           rom_cs,
    output reg           ram_cs,
    output reg           vram_cs,
    output reg           scr_cs,
    output reg           pal_cs,
    output reg           obj_cs,

    output reg    [ 2:0] obj_pal,
    input         [15:0] oram_dout,
    input         [15:0] pal_dout,
    input         [15:0] ram_dout,
    input         [15:0] rom_data,
    input                ram_ok,
    input                rom_ok,

    input                odakn,
    input                sdakn,

    // Sound interface
    input         [ 3:0] sn_dout,
    output reg           sn_we,
    output reg           sn_rd,

    // This interface shown in the
    // sch. seems to go to a test board
    output reg           snd_rstn,
    output reg           mintn,

    // --- DELTA opwolf ---
    output reg           cchip_cs,   // 0x0f0000-0x0fffff
    output reg           asic_cs,    // 0x0f0800-0x0f0fff
    input         [ 7:0] cchip_dout,
    input         [ 8:0] gun_x,      // pistola: contadores latcheados (esquemáticos §5)
    input         [ 8:0] gun_y,
    output reg           gun_latch,  // spritectrl bit 4 -> habilita el latch en vblank
    output reg    [ 1:0] motor,      // spritectrl bits 0-1 -> motor de retroceso
    output reg           cchip_rstn, // spritectrl bit 2 (activo bajo) -> reset C-Chip + PC050CM

    input         [ 5:0] joystick1,
    input         [ 5:0] joystick2,
    input         [ 1:0] cab_1p,
    input         [ 1:0] coin,
    input                service,
    input                tilt,
    input                dip_test,
    input                dip_pause,
    input         [ 7:0] dipsw_a,
    input         [ 7:0] dipsw_b
);
`ifndef NOMAIN
wire [23:1] A;
wire        cpu_cen, cpu_cenb;
wire        UDSn, LDSn, RnW, allFC, ASn, VPAn, DTACKn;
wire [ 2:0] FC, IPLn;
reg         io_cs, out_cs, inport_cs, gun_cs, wdog_cs;
reg  [ 7:0] cab_dout;
reg  [15:0] cpu_din;
wire [15:0] cpu_dout;
reg         intn, LVBLl;
wire        bus_cs, bus_busy, bus_legit;

assign main_addr= A[18:1];
assign main_dsn = {UDSn, LDSn};
assign main_rnw = RnW;
assign main_dout= cpu_dout;
assign allFC    = ~&FC; // allFC is high if the CPU is not accessing the "CPU space"
assign IPLn     = { intn, 1'b1, intn };
assign VPAn     = !(!ASn && FC==7 && A[3:1]==5 && RnW);
assign bus_cs   = rom_cs | vram_cs | ram_cs;
assign bus_busy = (rom_cs & ~rom_ok) | ( (vram_cs | ram_cs) & ~ram_ok);
assign bus_legit= vram_cs & ~sdakn;


// Mapa de Operation Wolf (mame-src/taito/opwolf.cpp -> opwolf_map). Delta vs rastan:
//   000000-03ffff  ROM (256 KB, no 384 KB)
//   0f0000-0f0fff  C-Chip (mirror 0xf000): 0f0000-0f07ff RAM compartida | 0f0800-0f0fff regs ASIC
//   100000-107fff  work RAM (32 KB)
//   200000-200fff  paleta
//   380000/2       R: DSWA/DSWB   W: spritectrl (colbank sprites, latch pistola, reset C-Chip, motor)
//   3a0000/2       R: pistola X / Y (contadores de 9 bits latcheados, esquemáticos §5)
//   3c0000         W: watchdog
//   3e0000/2       PC060HA (CIU) — OJO: bytes en direcciones PARES -> carril ALTO (UDS)
//   c00000-c0ffff  PC080SN | c20000/c40000/c50000 scroll+ctrl | d00000-d03fff PC090OJ
always @* begin
    rom_cs   = allFC && A[23:18]==6'd0 && !ASn;                 // 000000-03ffff
    cchip_cs = allFC && A[23:16]==8'h0f && !ASn;                // 0f0000-0fffff (mirror 0xf000)
    vram_cs  = allFC && A[23:19]==5'h18 && !ASn && {UDSn,LDSn}!=3;
    ram_cs   = allFC && A[23:18]==6'h4  && !ASn && {UDSn,LDSn}!=3;
    obj_cs   = allFC && A[23:20]==4'hd && !ASn;
    io_cs    = allFC && A[23:20]==4'h3 && !ASn;
    pal_cs   = allFC && A[23:18]==6'h8 && !ASn;
    // Video control registers are not written to SDRAM
    if( vram_cs && A[18:16]!=0 ) begin
        scr_cs  = 1;
        vram_cs = 0;
    end else begin
        scr_cs  = 0;
    end

    asic_cs    = cchip_cs & A[11];                              // 0f0800-0f0fff
    out_cs     = 0;   // spritectrl (0x380000)
    gun_cs     = 0;   // 0x3a0000/2
    wdog_cs    = 0;   // 0x3c0000
    sn_we      = 0;
    sn_rd      = 0;
    inport_cs  = 0;   // DSWA/DSWB (0x380000/2 en lectura)
    if( io_cs ) case( A[19:17] )
        3'b100: if( RnW ) inport_cs = 1; else out_cs = 1;       // 0x38xxxx
        3'b101: if( RnW ) gun_cs    = 1;                        // 0x3axxxx
        3'b110: if(!RnW ) wdog_cs   = 1;                        // 0x3cxxxx
        // 0x3exxxx: PC060HA. Byte en dirección PAR -> carril ALTO (UDS), NO LDS como en rastan.
        // ⚠ TODO Fase 3: confirmar carril con el sim (clase de bug byte-lane, GOTCHAS §A2/§B2).
        3'b111: if( !UDSn ) begin
                    if( RnW ) sn_rd = 1; else sn_we = 1;
                end
        default:;
    endcase
end

// IN2 (0x3a0000) e IN3 (0x3a0002): los 9 bits BAJOS son la pistola (mascara 0x01ff del driver);
// los ALTOS llevan los inputs de cabina. En opwolf van por el C-Chip y MAME los declara
// IPT_UNUSED ACTIVOS A NIVEL BAJO -> se leen como "no pulsado" (1). En opwolfp (sin C-Chip) SI
// se usan y el mapeo es este (opwolf.cpp, INPUT_PORTS opwolfp).
// ⚠ Todo activo a nivel BAJO salvo las MONEDAS de IN3, que son ACTIVAS A NIVEL ALTO.
// ⚠ Bug que costo un arranque: con los bits altos a CERO, el bit 12 de IN2 (TILT, activo bajo)
//   quedaba SIEMPRE activo y el juego arrancaba clavado en la pantalla "TILT".
wire [15:0] in2 = { 2'b00,            // 15-14: sin uso (activos a nivel alto)
                    cab_1p[0],        // 13: START1
                    tilt,             // 12: TILT
                    service,          // 11: SERVICE1
                    joystick1[5],     // 10: BUTTON2 (granada)
                    joystick1[4],     //  9: BUTTON1 (gatillo)
                    gun_x };          // 8-0: posicion X de la pistola
wire [15:0] in3 = { 5'b0,             // 15-11: sin uso
                    ~coin[1],         // 10: COIN2  (ACTIVA A NIVEL ALTO)
                    ~coin[0],         //  9: COIN1  (ACTIVA A NIVEL ALTO)
                    gun_y };          // 8-0: posicion Y de la pistola

always @(posedge clk) begin
    cpu_din <= rom_cs    ? rom_data :
               ( ram_cs | vram_cs ) ? ram_dout :
               obj_cs    ? oram_dout :
               pal_cs    ? pal_dout  :
               cchip_cs  ? { 8'hff, cchip_dout } :   // umask 0x00ff: sólo el byte bajo
               inport_cs ? { 8'hff, cab_dout }  :
               gun_cs    ? ( A[1] ? in3 : in2 ) :
               sn_rd     ? { 12'hfff, sn_dout } :
               16'hffff;
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        LVBLl <= 0;
    end else begin
        LVBLl <= LVBL;
        if( !VPAn )
            intn <= 1;
        else if( !LVBL && LVBLl )
            intn <= 0;
    end
end

function [5:0] mapjoy( input [5:0] j );
    mapjoy = { j[5:4], j[0], j[1], j[2], j[3] };
endfunction


// spritectrl_w (0x380000) — de opwolf.cpp:
//   bit 0-1 = transistores MOTOR1/MOTOR2 (retroceso)
//   bit 2   = reset del C-Chip y del PC050CM (activo bajo)
//   bit 4   = LATCH: habilita latchear la posición de la pistola en vblank
//   bit 5-7 = banco de paleta de los sprites  -> colbank = (sprite_ctrl & 0xe0) >> 1
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        obj_pal    <= 0;
        mintn      <= 0;
        snd_rstn   <= 0;
        cab_dout   <= 0;
        gun_latch  <= 0;
        motor      <= 0;
        cchip_rstn <= 1;
    end else begin
        if( out_cs ) begin
            obj_pal    <= cpu_dout[7:5];
            gun_latch  <= cpu_dout[4];
            // ⚠ bit2 = "reset C-Chip + PC050CM" (activo bajo) EN EL PCB, pero MAME (que emula el
            //   uPD78C11 REAL) NUNCA resetea el C-Chip desde aqui: spritectrl_w solo toca
            //   sprite_ctrl (paleta/prioridad) y el motor (opwolf.cpp:634-651). El mapa lo remata:
            //   "usually 0x4, changes when you fire" -> en juego el bit2 se queda a 1.
            //   Aplicarlo (como haciamos) reseteaba el C-Chip en cada pulso del 68000:
            //     - con cycle-timing a velocidad real -> bucle de reset -> NO ARRANCA (patron test, §0-BIS)
            //     - al disparar/pulsar -> se pierde el debounce del firmware -> "coge varias pulsaciones"
            //   Lo IGNORAMOS como MAME: el C-Chip solo se resetea con el reset GLOBAL (cchip_rstn=1).
            // cchip_rstn <= cpu_dout[2];   // <- causa de la regresion; ver HANDOFF §0-BIS / GOTCHAS
            motor      <= cpu_dout[1:0];
        end
        // Lectura en 0x380000/2: A[1]=0 -> DSWA, A[1]=1 -> DSWB
        // ⚠ Los inputs de jugador (monedas, gatillo, granada, start, service, tilt) NO están en el
        //    bus del 68000: entran por los puertos PB/PC del C-Chip (opwolf.cpp, in_pb/in_pc_callback).
        cab_dout <= A[1] ? dipsw_b : dipsw_a;
    end
end

// ---------------------------------------------------------------- DEBUG spritectrl / reset C-Chip
// El bit 2 de 0x380000 resetea el C-Chip (activo bajo). MAME lo IGNORA; el RTL lo aplica.
// Si el 68000 lo togglea durante el attract, el C-Chip se reinicia y pierde el debounce de entradas.
`ifdef SIMULATION
reg cchip_rstn_l=1;
always @(posedge clk) begin
    cchip_rstn_l <= cchip_rstn;
    if( out_cs )
        $display("%9t 68000 -> SPRITECTRL = %02X  (bit2/cchip_rstn=%0d)", $time, cpu_dout, cpu_dout[2]);
    if( cchip_rstn_l !== cchip_rstn )
        $display("%9t *** cchip_rstn %0d -> %0d ***", $time, cchip_rstn_l, cchip_rstn);
end
`endif

jtframe_68kdtack_cen #(.W(8)) u_dtack(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cpu_cen    ( cpu_cen   ),
    .cpu_cenb   ( cpu_cenb  ),
    .bus_cs     ( bus_cs    ),
    .bus_busy   ( bus_busy  ),
    .bus_legit  ( bus_legit ),
    .bus_ack    ( 1'b0      ),
    .ASn        ( ASn       ),
    .DSn        ({UDSn,LDSn}),
    // clk = clk_rom = clk48 = 53.365 MHz (JTFRAME_MCLK), NO 26.686 (eso es clk24). El 68000 real va
    // a 8 MHz (16 MHz XTAL / 2, opwolf.cpp:840). 3/20 * 53.365 = 8.005 MHz.
    // (3/10 daba 16 MHz -> juego 2x rapido en placa. Ver memoria clk-real-es-clk48-no-26686.)
    .num        ( 7'd3      ),  // numerator
    .den        ( 8'd20     ),  // denominator
    .DTACKn     ( DTACKn    ),
    .wait2      ( 1'b0      ),
    .wait3      ( 1'b0      ),
    // Frequency report
    .fave       (           ),
    .fworst     (           )
);

jtframe_m68k u_cpu(
    .clk        ( clk         ),
    .rst        ( rst         ),
    .RESETn     (             ),
    .cpu_cen    ( cpu_cen     ),
    .cpu_cenb   ( cpu_cenb    ),

    // Buses
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout    ),


    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( VPAn        ),
    .FC         ( FC          ),

    .BERRn      ( 1'b1        ),
    // Bus arbitrion
    .HALTn      ( dip_pause   ),
    .BRn        ( 1'b1        ),
    .BGACKn     ( 1'b1        ),
    .BGn        (             ),

    .DTACKn     ( DTACKn      ),
    .IPLn       ( IPLn        ) // VBLANK
);
`else
assign main_addr=0, main_dsn=0, main_dout=0, main_rnw=0;
initial begin
    rom_cs   = 0;
    ram_cs   = 0;
    vram_cs  = 0;
    scr_cs   = 0;
    pal_cs   = 0;
    obj_cs   = 0;
    obj_pal  = 0;
    sn_we    = 0;
    sn_rd    = 0;
    snd_rstn = 0;
    mintn    = 0;
end
`endif
endmodule
