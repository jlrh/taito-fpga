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

// This module implements the pc080sn logic
// The original clock was 26.686MHz/2 = 13.343MHz
// Using 48MHz as basis, the ratio is 1073/3860
// Measurements on Operation Wolf reported in MAME
//    VSync - 60.0551Hz
//    HSync - 15.6742kHz

module opwolf_scr(
    input           rst,
    input           clk,
    output          pxl_cen,
    output          pxl2_cen,

    output          HS,
    output          VS,
    output          LHBL,
    output          LVBL,
    output reg      flip,
    output   [ 8:0] hdump,
    output   [ 8:0] vrender,

    input    [18:1] main_addr,
    input    [15:0] main_dout,
    input    [ 1:0] main_dsn,
    input           main_rnw,
    input           scr_cs,        // selection from address decoder
    output          dtackn,

    output   [15:2] ram0_addr,
    input    [31:0] ram0_data,
    input           ram0_ok,
    output          ram0_cs,

    output   [19:2] rom0_addr,
    input    [31:0] rom0_data,
    input           rom0_ok,
    output          rom0_cs,

    output   [15:2] ram1_addr,
    input    [31:0] ram1_data,
    input           ram1_ok,
    output          ram1_cs,

    output   [19:2] rom1_addr,
    input    [31:0] rom1_data,
    input           rom1_ok,
    output          rom1_cs,

    output   [10:0] scr1_pxl,
    output   [10:0] scr0_pxl,
    input    [ 7:0] debug_bus,
    output   [ 7:0] debug_view
);

wire [ 8:0] vdump;
reg  [15:0] scr0_hpos, scr1_hpos, scr0_vpos, scr1_vpos;

assign dtackn = 0;
// ⚠ NO conectar sondas a debug_view en un build de release: jtframe pinta ese byte SOBRE la imagen
// (jtframe_debug_ctrl: el overlay se enciende con debug_view!=0). Una sonda al scroll del BG deja
// numeros permanentes en pantalla, que cambian con el scroll. Ver GOTCHAS §H25.
assign debug_view = 8'd0;
/*
reg LVBLl;

always @(posedge clk) begin
    LVBLl <= LVBL;
    if( ~LVBL && LVBLl ) scr0_hpos <= scr0_hpos + 1'd1;
end
*/
// SIMULACIÓN DE ESCENA (NOMAIN): sin 68000 nadie escribe los vregs de scroll. Se precargan desde
// vregs.hex (el mismo volcado de la Fase 0: ysBG ysFG xsBG xsFG ctrl - sprctrl -).
// Sin esto, el sim renderiza con scroll 0 y NUNCA puede igualar al golden.
`ifdef NOMAIN
reg [15:0] vregs_ini[0:7];
initial $readmemh("vregs.hex", vregs_ini);
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
`ifdef NOMAIN
        scr0_vpos <= vregs_ini[0];
        scr1_vpos <= vregs_ini[1];
        scr0_hpos <= vregs_ini[2];
        scr1_hpos <= vregs_ini[3];
        flip      <= vregs_ini[4][0];
`else
        scr0_hpos <= 0;
        scr1_hpos <= 0;
        scr0_vpos <= 0;
        scr1_vpos <= 0;
`endif
    end else if(scr_cs && !main_rnw) begin
        case( {main_addr[18:16],main_addr[1]} )
            {3'd2,1'b0}: scr0_vpos <= main_dout;
            {3'd2,1'b1}: scr1_vpos <= main_dout;
            {3'd4,1'b0}: scr0_hpos <= main_dout;
            {3'd4,1'b1}: scr1_hpos <= main_dout;
            {3'd5,1'b0}: flip      <= main_dout[0];
            default:;
        endcase
    end
end

// OJO con la convencion de jtframe_frac_cen: cen[0] es la frecuencia BASE (n/m*clk) y cen[1] es
// la mitad. Como aqui se conecta {pxl_cen, pxl2_cen}, resulta pxl_cen = cen[1] = BASE/2 = clk*n/m/2.
// clk = clk_rom = clk48 = 53.365 MHz (JTFRAME_MCLK), NO 26.686 (eso es clk24). Para pixel clock
// 6.6715 MHz -> pxl_cen = clk/8 -> n/m = 1/4; pxl2_cen = cen[0] = clk/4 = 13.343 MHz (2x pixel).
// (Antes n/m=1/2 asumiendo clk=26.686 -> en placa pixel 13.34 MHz = 120 Hz / HSync 31 kHz, fuera
//  del rango de un CRT. Ver memoria clk-real-es-clk48-no-26686.)
jtframe_frac_cen #(
    .W (  2 )
) u_cen (
    .clk    ( clk       ),
    .n      ( 10'd1     ),         // numerator
    .m      ( 10'd4     ),         // denominator (clk 53.365 MHz -> pxl_cen 6.6715 MHz)
    .cen    ({pxl_cen,pxl2_cen}),
    .cenb   (           )
);

// Timing de Operation Wolf — NO es el de Rastan (ver research/ESQUEMATICOS-OPWOLF.md §2).
// El sync lo genera el ASIC PC080SN, así que NO sale del esquemático (GAPS-REPORT.md §G-11).
// Derivado de las medidas del PCB (cabecera de opwolf.cpp): VSync 60.0551 Hz, HSync 15.6742 kHz,
// pixel clock = 26.68558/4 = 6.6714 MHz:
//     VTOTAL = 15674.2 / 60.0551      = 261 líneas   (rastan: ~263)
//     HTOTAL = 6.6714e6 / 15674.2     ≈ 426 dots     (rastan:  424)
// Área visible (MAME): 320x240, visarea(0..319, 8..247).
// ⚠ FASE 2: confirmar HB/VS/HS contra el golden y las capturas de MAME antes de dar esto por bueno.
jtframe_vtimer #(
    .VB_START   ( 9'd239          ),
    .VB_END     ( 9'd239+9'd21    ),  // VTOTAL = 261
    .VS_START   ( 9'd239+9'd7     ),
    .HB_END     ( 9'hF            ),
    .HB_START   ( 9'h14F          ),
    .HCNT_END   ( 9'd319+9'd106   ),  // HTOTAL = 426
    .HS_START   ( 9'd320+9'd44    )
) u_vtimer(
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   (           ),
    .H          ( hdump     ),
    .Hinit      (           ),
    .Vinit      (           ),
    .LHBL       ( LHBL      ),
    .LVBL       ( LVBL      ),
    .HS         ( HS        ),
    .VS         ( VS        )
);

opwolf_tilemap u_scr0( // background
    .rst        ( rst       ),
    .clk        ( clk       ),

    .flip       ( flip      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),

    .hpos       ( scr0_hpos[8:0] ),
    .vpos       ( scr0_vpos[8:0] ),

    .ram_addr   ( ram0_addr ),
    .ram_data   ( ram0_data ),
    .ram_ok     ( ram0_ok   ),
    .ram_cs     ( ram0_cs   ),

    .rom_addr   ( rom0_addr ),
    .rom_data   ( rom0_data ),
    .rom_ok     ( rom0_ok   ),
    .rom_cs     ( rom0_cs   ),

    .pxl        ( scr0_pxl  ),
    .debug_bus  ( debug_bus )
);

opwolf_tilemap #(1) u_scr1( // foreground
    .rst        ( rst       ),
    .clk        ( clk       ),

    .flip       ( flip      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),

    .hpos       ( scr1_hpos[8:0] ),
    .vpos       ( scr1_vpos[8:0] ),

    .ram_addr   ( ram1_addr ),
    .ram_data   ( ram1_data ),
    .ram_ok     ( ram1_ok   ),
    .ram_cs     ( ram1_cs   ),

    .rom_addr   ( rom1_addr ),
    .rom_data   ( rom1_data ),
    .rom_ok     ( rom1_ok   ),
    .rom_cs     ( rom1_cs   ),

    .pxl        ( scr1_pxl  ),
    .debug_bus  ( debug_bus )
);

endmodule
