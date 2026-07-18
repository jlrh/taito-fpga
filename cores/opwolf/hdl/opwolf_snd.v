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

    Operation Wolf (Taito, 1987) - core FPGA
    Basado en jtrastan_snd.v (misma placa), con el delta de sonido de opwolf.
    Date: 2026-07-14 */

// SONIDO DE OPERATION WOLF (opwolf.cpp)
//   Z80 @ 4 MHz (8 MHz XTAL / 2) | YM2151 @ 4 MHz | 2x MSM5205 @ 384 kHz (S48_4B -> 8 kHz)
//   PC060HA (CIU) para hablar con el 68000 | 2x TC0060DCA (volumen digital)
//
// MAPA DEL Z80 (opwolf_sound_z80_map) — ⚠ NO es el de rastan:
//   0000-3fff  ROM fija
//   4000-7fff  ROM banqueada (4 bancos de 16 KB) — el banco lo eligen CT1/CT2 del YM2151
//   8000-8fff  RAM (4 KB)
//   9000-9001  YM2151
//   a000-a001  PC060HA
//   b000-b006  banco de registros ADPCM del MSM5205 #0   <-- DELTA vs rastan
//   c000-c006  banco de registros ADPCM del MSM5205 #1   <-- DELTA vs rastan
//   d000       TC0060DCA[1] volumen 1 (maestro, canal izq)
//   e000       TC0060DCA[1] volumen 2 (maestro, canal der)
//
// rastan tenia UN MSM5205 con control simple (b000=addr, c000=start, d000=stop). Aqui cada
// canal tiene su propio banco de 7 registros: ver opwolf_adpcm.v.

module opwolf_snd(
    input                rst,
    input                clk,

    // From main CPU
    input                rst48,
    input                clk48,
    input                main_addr,
    input         [ 3:0] main_dout,
    output        [ 3:0] main_din,
    input                main_rnw,
    input                sn_rd,
    input                sn_we,

    // ROM del Z80: 64 KB (b20-07.10)
    output        [15:0] rom_addr,
    output reg           rom_cs,
    input                rom_ok,
    input         [ 7:0] rom_data,

    // ROM de muestras ADPCM: 512 KB (b20-08.21), COMPARTIDA por los dos MSM5205
    output        [18:0] pcm0_addr,
    output               pcm0_cs,
    input                pcm0_ok,
    input         [ 7:0] pcm0_data,

    output        [18:0] pcm1_addr,
    output               pcm1_cs,
    input                pcm1_ok,
    input         [ 7:0] pcm1_data,

    output signed [15:0] fm_l, fm_r,
    output signed [11:0] pcm0, pcm1
);

`ifndef NOSOUND
wire               cen4, cen2, pcm_cen, nc;
wire signed [11:0] snd0, snd1;
wire               int_n;
wire        [15:0] A;
wire        [ 7:0] dout, opm_dout, ram_dout;
wire        [ 3:0] pc6_dout;
reg                opm_cs, ram_cs, pc6_cs;
reg                adpcm0_we, adpcm1_we, dcaL_we, dcaR_we;
wire               m1_n, iorq_n, rd_n, wr_n, mreq_n, rfsh_n, nmi_n;
wire               ct1, ct2, pc6_rst;
reg                snd_rstn;
reg         [ 7:0] din;
wire               main_cs;

wire        [ 3:0] nib0, nib1;
wire               vclk0, vclk1, msm0_rst, msm1_rst;
wire               sample0, sample1;             // cen_lo del jt5205 (sonda del ADPCM)
wire        [ 7:0] vol0, vol1;                 // volumen por canal ADPCM (TC0060DCA[0])
reg         [ 7:0] volL, volR;                 // volumen maestro (TC0060DCA[1])
wire        [ 7:0] gain0, gain1, gainL, gainR;
wire signed [15:0] fm_pre_l, fm_pre_r;         // salida cruda del jt51, antes del volumen

assign main_cs  = sn_rd | sn_we;
// banco de la ROM del Z80: 4 x 16 KB. En MAME lo pone el port write del YM2151 (mask 0x03),
// que son sus pines CT1/CT2 -> aqui salen del jt51.
assign rom_addr = A[14] ? { ct2, ct1, A[13:0] } : A;

always @(posedge clk) begin
    snd_rstn <= ~(rst | pc6_rst);
end

// ---------------------------------------------------------------- decode del Z80
// ⚠ Las escrituras se convierten en un PULSO de 1 clk. Con el nivel (~wr_n) a pelo, el Z80 lo
// mantiene bajo varios ciclos de clk (su cen es 4 MHz sobre un clk de 26.7) y el DISPARO del ADPCM
// (reg 4) se re-ejecutaria en cada ciclo, reseteando la posicion una y otra vez.
reg wrl;
always @(posedge clk) wrl <= ~wr_n;
wire wr_pulse = ~wr_n & ~wrl;

always @* begin
    rom_cs    = !A[15] && !rd_n;
    ram_cs    = 0;
    opm_cs    = 0;
    pc6_cs    = 0;
    adpcm0_we = 0;
    adpcm1_we = 0;
    dcaL_we   = 0;
    dcaR_we   = 0;
    if( !mreq_n && rfsh_n && A[15] ) begin
        case( A[14:12] )
            3'd0: ram_cs    = 1;            // 8000-8fff
            3'd1: opm_cs    = 1;            // 9000-9001
            3'd2: pc6_cs    = 1;            // a000-a001
            3'd3: adpcm0_we = wr_pulse;     // b000-b006  (solo escritura)
            3'd4: adpcm1_we = wr_pulse;     // c000-c006  (solo escritura)
            3'd5: dcaL_we   = wr_pulse;     // d000
            3'd6: dcaR_we   = wr_pulse;     // e000
            default:;
        endcase
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        volL <= 8'hff;                      // MAME arranca con atten_table[0xff]
        volR <= 8'hff;
    end else begin
        if( dcaL_we ) volL <= dout;
        if( dcaR_we ) volR <= dout;
    end
end

always @(posedge clk) begin
    din <=  rom_cs ? rom_data :
            ram_cs ? ram_dout :
            opm_cs ? opm_dout :
            pc6_cs ? { 4'hf, pc6_dout } :
            8'hff;
end

// ---------------------------------------------------------------- relojes
// cen4 = 4 MHz (Z80 y YM2151), cen2 = 2 MHz (cen_p1 del jt51).
// OJO con jtframe_frac_cen: cen[0] es la BASE (n/m*clk) y cen[1] la mitad -> con
// .cen({cen2,cen4}) resulta cen4 = cen[0] = BASE. Ver GOTCHAS §H7.
jtframe_frac_cen #(.WC(11)) u_cpucen(
    .clk  ( clk          ),
    .n    ( 11'd231      ),
    .m    ( 11'd1541     ),
    .cen  ( {cen2,cen4 } ),
    .cenb (              )
);

// 384 kHz para los MSM5205 (S48_4B -> 8 kHz de muestreo)
jtframe_frac_cen #(.WC(8)) u_pcmcen(
    .clk  ( clk          ),
    .n    ( 8'd2         ),  // 2/139 * 26.686 MHz = 383.9 kHz
    .m    ( 8'd139       ),
    .cen  ({nc,pcm_cen } ),
    .cenb (              )
);

opwolf_pc060 u_pc060(
    .rst48      ( rst48     ),
    .clk48      ( clk48     ),
    .main_dout  ( main_dout ),
    .main_din   ( main_din  ),
    .main_addr  ( main_addr ),
    .main_rnw   ( main_rnw  ),
    .main_cs    ( main_cs   ),

    .rst24      ( rst       ),
    .clk24      ( clk       ),
    .snd_dout   ( dout[3:0] ),
    .snd_din    ( pc6_dout  ),
    .snd_addr   ( A[0]      ),
    .snd_rnw    ( wr_n      ),
    .snd_cs     ( pc6_cs    ),
    .snd_nmin   ( nmi_n     ),
    .snd_rst    ( pc6_rst   )
);

jtframe_sysz80 #(.RECOVERY(0)) u_cpu(
    .rst_n      ( snd_rstn  ),
    .clk        ( clk       ),
    .cen        ( cen4      ),
    .cpu_cen    (           ),
    .int_n      ( int_n     ),
    .nmi_n      ( nmi_n     ),
    .busrq_n    ( 1'b1      ),
    .m1_n       ( m1_n      ),
    .mreq_n     ( mreq_n    ),
    .iorq_n     ( iorq_n    ),
    .rd_n       ( rd_n      ),
    .wr_n       ( wr_n      ),
    .rfsh_n     ( rfsh_n    ),
    .halt_n     (           ),
    .busak_n    (           ),
    .A          ( A         ),
    .cpu_din    ( din       ),
    .cpu_dout   ( dout      ),
    .ram_dout   ( ram_dout  ),
    .ram_cs     ( ram_cs    ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

jt51 u_jt51(
    .rst    ( ~snd_rstn ),
    .clk    ( clk       ),
    .cen    ( cen4      ),
    .cen_p1 ( cen2      ),
    .cs_n   ( ~opm_cs   ),
    .wr_n   ( wr_n      ),
    .a0     ( A[0]      ),
    .din    ( dout      ),
    .dout   ( opm_dout  ),
    .ct1    ( ct1       ),      // -> banco de la ROM del Z80
    .ct2    ( ct2       ),
    .irq_n  ( int_n     ),
    .sample (           ),
    .left   (           ),
    .right  (           ),
    .xleft  ( fm_pre_l  ),
    .xright ( fm_pre_r  )
);

// ---------------------------------------------------------------- ADPCM x2
opwolf_adpcm u_adpcm0(
    .rst      ( rst        ),
    .clk      ( clk        ),
    .addr     ( A[2:0]     ),
    .din      ( dout       ),
    .we       ( adpcm0_we  ),
    .rom_addr ( pcm0_addr  ),
    .rom_cs   ( pcm0_cs    ),
    .rom_data ( pcm0_data  ),
    .rom_ok   ( pcm0_ok    ),
    .vclk     ( vclk0      ),
    .snd_sample( sample0   ),
    .nibble_v ( nib0       ),
    .msm_rst  ( msm0_rst   ),
    .vol      ( vol0       )
);

opwolf_adpcm u_adpcm1(
    .rst      ( rst        ),
    .clk      ( clk        ),
    .addr     ( A[2:0]     ),
    .din      ( dout       ),
    .we       ( adpcm1_we  ),
    .rom_addr ( pcm1_addr  ),
    .rom_cs   ( pcm1_cs    ),
    .rom_data ( pcm1_data  ),
    .rom_ok   ( pcm1_ok    ),
    .vclk     ( vclk1      ),
    .snd_sample( sample1   ),
    .nibble_v ( nib1       ),
    .msm_rst  ( msm1_rst   ),
    .vol      ( vol1       )
);

jt5205 u_msm0( // 8 kHz, 4 bits/muestra
    .rst    ( msm0_rst  ),
    .clk    ( clk       ),
    .cen    ( pcm_cen   ),
    .sel    ( 2'b10     ),      // S48_4B -> 384k/48 = 8 kHz
    .din    ( nib0      ),
    .sound  ( snd0      ),
    .sample ( sample0   ),
    .irq    (           ),
    .vclk_o ( vclk0     )
);

jt5205 u_msm1(
    .rst    ( msm1_rst  ),
    .clk    ( clk       ),
    .cen    ( pcm_cen   ),
    .sel    ( 2'b10     ),
    .din    ( nib1      ),
    .sound  ( snd1      ),
    .sample ( sample1   ),
    .irq    (           ),
    .vclk_o ( vclk1     )
);

// ---------------------------------------------------------------- TC0060DCA (volumen digital)
// DCA[0]: atenua cada MSM5205 con el reg 5 de SU banco ADPCM.
// DCA[1]: volumen MAESTRO (Z80 d000/e000) sobre TODO (ADPCM + FM).
// ⚠ Simplificacion: jtframe mezcla pcm0/pcm1 como canales MONO (mem.yaml), asi que no pueden
//    llevar ganancia L/R distinta -> les aplico la maestra IZQUIERDA. El FM (jt51 es estereo)
//    si lleva L y R por separado. En la practica el juego escribe d000 == e000.
opwolf_dca u_dca_ch0( .clk(clk), .vol(vol0), .gain(gain0) );
opwolf_dca u_dca_ch1( .clk(clk), .vol(vol1), .gain(gain1) );
opwolf_dca u_dca_mL ( .clk(clk), .vol(volL), .gain(gainL) );
opwolf_dca u_dca_mR ( .clk(clk), .vol(volR), .gain(gainR) );

// (muestra * gain) >>> 8, con la ganancia en 1/256
opwolf_vol #(.DW(12)) u_vol0( .clk(clk), .gain(gain0), .gmaster(gainL), .sin(snd0    ), .sout(pcm0) );
opwolf_vol #(.DW(12)) u_vol1( .clk(clk), .gain(gain1), .gmaster(gainL), .sin(snd1    ), .sout(pcm1) );
opwolf_vol #(.DW(16)) u_volL( .clk(clk), .gain(8'd255),.gmaster(gainL), .sin(fm_pre_l), .sout(fm_l) );
opwolf_vol #(.DW(16)) u_volR( .clk(clk), .gain(8'd255),.gmaster(gainR), .sin(fm_pre_r), .sout(fm_r) );

`else
assign main_din=0, rom_addr=0, fm_l=0, fm_r=0, pcm0=0, pcm1=0;
assign pcm0_addr=0, pcm1_addr=0, pcm0_cs=0, pcm1_cs=0;
initial rom_cs=0;
`endif
endmodule
