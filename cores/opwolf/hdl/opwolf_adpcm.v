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
    Date: 2026-07-14 */

// Motor ADPCM de Operation Wolf: banco de registros + secuenciador de un MSM5205.
// opwolf lleva DOS (rastan solo uno, y con un control mucho mas simple).
//
// BANCO DE REGISTROS (opwolf.cpp: adpcm_w<N>). Z80: 0xb000-0xb006 (N=0) / 0xc000-0xc006 (N=1):
//   reg 0 = start LSB     reg 1 = start MSB
//   reg 2 = end   LSB     reg 3 = end   MSB
//   reg 4 = RUN  -> ESCRIBIR AQUI DISPARA la reproduccion (el dato da igual)
//   reg 5 = VOL  -> volumen, se aplica al TC0060DCA[0] EN EL DISPARO
//   reg 6 = RES          reg 7 = N/C
//
// ⚠ start y end estan en unidades de 16 BYTES: la direccion real es (reg<<4).
//
// SECUENCIA (opwolf.cpp: msm5205_vck_w<N>) - dos VCK por byte:
//   VCK impar : lee el byte en pos, entrega el nibble ALTO, pos++
//   VCK par   : entrega el nibble BAJO; si pos == end -> PARA (reset del MSM)
// El contador {pos, nib} incrementa en cada VCK: nib=0 -> alto, nib=1 -> bajo.
//
// A 8 kHz hay ~3300 ciclos de clk entre VCK: en REGIMEN PERMANENTE sobra tiempo para que la SDRAM
// sirva el byte, y basta con mantener rom_cs y dejar rom_addr = pos (igual que hace rastan).
// ⚠ PERO ESO NO VALE PARA EL PRIMER BYTE DE CADA MUESTRA: en el disparo no hay 3300 ciclos de
// margen, hay CERO. Ver el comentario del `trigger` mas abajo. Por eso se espera a rom_ok.
// Ademas, la primera lectura de cada muestra es un FALLO DE CACHE seguro (direccion nueva), asi
// que es justo la mas lenta; las de regimen permanente aciertan en el block-cache del romrq.

module opwolf_adpcm(
    input             rst,
    input             clk,

    // banco de registros (bus del Z80)
    input      [ 2:0] addr,
    input      [ 7:0] din,
    input             we,

    // ROM de muestras ADPCM (512 KB, COMPARTIDA por los dos canales)
    output     [18:0] rom_addr,
    output reg        rom_cs,
    input      [ 7:0] rom_data,
    input             rom_ok,      // SOLO SONDA (de momento): no altera el comportamiento

    // hacia el MSM5205
    input             vclk,        // VCK que devuelve el jt5205
    input             snd_sample,  // cen_lo del jt5205 = instante en que CONSUME el nibble (sonda)
    output     [ 3:0] nibble_v,    // nibble a reproducir
    output reg        msm_rst,     // 1 = MSM parado (reset)

    output reg [ 7:0] vol          // reg 5, latcheado en el disparo (para el TC0060DCA)
);

reg  [ 7:0] regs[0:7];
reg  [18:0] pos, endpos;
reg         nib;                    // 0 = nibble alto, 1 = nibble bajo
reg         vclk_l;
reg         pending;                // disparado, esperando a que la SDRAM sirva el PRIMER byte

wire [15:0] start_r = { regs[1], regs[0] };
wire [15:0] end_r   = { regs[3], regs[2] };
wire        trigger = we && addr==3'd4;          // escribir en el reg 4 = RUN
wire [18:0] nxt_pos = pos + 19'd1;

assign rom_addr = pos;
assign nibble_v = nib ? rom_data[3:0] : rom_data[7:4];

integer i;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        for( i=0; i<8; i=i+1 ) regs[i] <= 8'd0;
        pos     <= 19'd0;
        endpos  <= 19'd0;
        nib     <= 1'b0;
        msm_rst <= 1'b1;            // arranca parado
        rom_cs  <= 1'b0;
        vol     <= 8'd0;
        vclk_l  <= 1'b0;
        pending <= 1'b0;
    end else begin
        vclk_l <= vclk;
        if( we ) regs[addr] <= din;

        if( trigger ) begin
            // pos = start<<4, end = end<<4  (mask 0x7ffff = ROM de 512 KB)
            pos     <= { start_r[14:0], 4'd0 };
            endpos  <= { end_r  [14:0], 4'd0 };
            nib     <= 1'b0;
            rom_cs  <= 1'b1;
            vol     <= regs[5];     // el volumen se captura EN EL DISPARO (como MAME)
            // ⭐ El MSM se queda EN RESET hasta que la SDRAM sirva el primer byte. NO se puede
            // soltar aqui: jt5205_timing NO tiene reset (su divisor corre libre desde el
            // power-up), asi que el primer cen_lo -el instante en que el MSM CAPTURA el nibble-
            // cae en un punto ALEATORIO de una ventana de 125 us... que puede ser AHORA MISMO.
            // Si eso pasa antes de rom_ok, rom_data todavia tiene el byte de la muestra ANTERIOR
            // y el nibble es basura. Y como el ADPCM es diferencial y con estado, ese nibble
            // dispara el indice de paso (+8 de golpe, jt5205_adpcm.v:58) con el indice recien
            // reseteado a 0 -> la muestra ENTERA sale distorsionada, no un clic.
            // El retardo que introduce esto es <1 us sobre un periodo de muestreo de 125 us.
            msm_rst <= 1'b1;
            pending <= 1'b1;
        end else if( pending ) begin
            if( rom_ok ) begin      // primer byte ya servido -> ahora si, a reproducir
                msm_rst <= 1'b0;
                pending <= 1'b0;
            end
        end else if( vclk && !vclk_l && !msm_rst ) begin
            { pos, nib } <= { pos, nib } + 1'd1;
            // el fin se comprueba tras entregar el nibble BAJO, con pos ya incrementada
            if( nib && nxt_pos==endpos ) begin
                msm_rst <= 1'b1;
                rom_cs  <= 1'b0;
            end
        end
    end
end

// ---------------------------------------------------------------- SONDA (solo simulacion)
// HIPOTESIS A MEDIR: el PRIMER byte de cada muestra se consume ANTES de que la SDRAM lo sirva.
// El divisor de jt5205_timing NO tiene reset (corre libre desde el power-up), asi que el primer
// cen_lo tras el disparo cae en un instante ALEATORIO entre 0 y 125 us. Si cae antes de que
// llegue rom_ok, el nibble es basura -> como ADPCM es diferencial, el indice de paso se dispara
// y la muestra entera sale distorsionada.
// Emite UNA linea por disparo; el resumen lo hace tools/opwolf_adpcm_probe.py sobre el log.
`ifdef SIMULATION
integer clk_cnt = 0;
integer t_trig  = 0;
reg     await_first = 0;

// Latencia de CADA lectura: de que cambia la direccion hasta que sube rom_ok.
// La PRIMERA lectura de cada muestra (first=1) es un FALLO DE CACHE seguro: direccion nueva y
// aleatoria. Las de regimen permanente casi siempre aciertan en el block-cache del
// jtframe_romrq_bcache -> lat=0. Por eso el disparo es el peor caso.
reg [18:0] pos_l;
integer    lat_cnt = 0;
reg        lat_run = 0, lat_first = 0, first_pending = 0;

always @(posedge clk) begin
    clk_cnt <= clk_cnt + 1;
    pos_l   <= pos;
    if( rst ) begin
        await_first   <= 0;
        lat_run       <= 0;
        first_pending <= 0;
    end else begin
        // ---- latencia de lectura
        if( trigger ) first_pending <= 1;
        if( rom_cs && pos != pos_l ) begin
            lat_run       <= 1;
            lat_cnt       <= 0;
            lat_first     <= first_pending;
            first_pending <= 0;
        end else if( lat_run ) begin
            if( rom_ok ) begin
                lat_run <= 0;
                $display("ADPCM-LAT %m lat=%0d first=%b", lat_cnt, lat_first);
            end else begin
                lat_cnt <= lat_cnt + 1;
            end
        end
        // ---- disparo -> captura del primer nibble
        if( trigger ) begin
            await_first <= 1;
            t_trig      <= clk_cnt;
        end else if( await_first && snd_sample ) begin
            await_first <= 0;
            // dly = clks entre el disparo y el instante en que el MSM captura el primer nibble.
            //       Por el divisor libre de jt5205_timing (sin reset) esto es UNIFORME en [0,3300].
            // ok  = 0 -> el byte NO habia llegado: nibble BASURA (el de la muestra anterior)
            // nib = 1 -> se colo el nibble BAJO primero (MAME entrega el ALTO): orden invertido
            $display("ADPCM-PROBE %m dly=%0d ok=%b nib=%b pos=%h data=%h",
                     clk_cnt - t_trig, rom_ok, nib, pos, rom_data);
        end
    end
end
`endif

endmodule
