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

// SUSTITUTO DEL C-CHIP  (FASE 4 — camino HLE via bootleg; la decision esta en research/OPWOLF-PLAN.md)
//
// El C-Chip real (TC0030CMD) es un **uPD78C11** y NO existe core de esa CPU en jtframe. El bootleg
// 'opwolfb' lo sustituye por un **Z80 con ROM de 32 KB dumpeada** (opwlfb.09): esa ROM ES la HLE del
// C-Chip, ya escrita y validada por los autores del bootleg. jtframe SI tiene Z80 -> camino elegido.
//
// ⚠ La proteccion es ACTIVA y ADEMAS ES DUEÑA DE LOS INPUTS: lee monedas/gatillo/start por sus
//   puertos y los deja en la RAM compartida. Sin ella no hay ni creditos ni disparo.
//
// INTERFAZ (opwolf.cpp: opwolfb_map + opwolfb_sub_z80_map)
//   Lado 68000: 0x0f0000-0x0f0fff -> RAM compartida de 2 KB.
//        ⚠ UNA PALABRA del 68000 = UN BYTE de la RAM. En MAME es literalmente
//          `m_cchip_ram[offset]` con offset = indice de PALABRA -> aqui el indice es A[11:1].
//   Lado Z80:   0000-7fff ROM (32 KB) | 8800 = IN1 | 9800 = IN0
//               9000 y a000 = escrituras que se ignoran (ack de IRQ)
//               c000-c7ff = RAM compartida
//   IRQ:        vblank -> INT del Z80 (irq0_line_hold: se mantiene hasta que la CPU la reconoce)
//
// ⚠ El 68000 del bootleg esta PARCHEADO: no usa los registros ASIC del C-Chip real (0x0f0800), asi
//   que esta ROM NO sirve para el set ORIGINAL. El original sigue bloqueado a falta de un uPD7811.

module opwolf_cchip(
    input             rst,
    input             clk,
    input             cen4,        // 4 MHz para el Z80 sustituto

    // interfaz 68000 (RAM compartida)
    input      [11:1] addr,
    input      [ 7:0] din,
    output     [ 7:0] dout,
    input             cs,
    input             rnw,

    // ROM del Z80 sustituto (32 KB, opwlfb.09)
    output     [14:0] rom_addr,
    output reg        rom_cs,
    input             rom_ok,
    input      [ 7:0] rom_data,

    input             LVBL,        // vblank -> IRQ

    // inputs de cabina: en el PCB real entran por los puertos del C-Chip, NO por el bus del 68000
    input      [ 7:0] cab_in0,     // monedas
    input      [ 7:0] cab_in1,     // gatillo, granada, service, tilt, start

    output     [ 7:0] st_dout      // debug
);

wire [15:0] A;
wire [ 7:0] cpu_dout, ram_dout;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
reg  [ 7:0] cpu_din;
reg         ram_cs, in0_cs, in1_cs;
reg         int_n, lvbl_l;
wire        irq_ack = ~m1_n & ~iorq_n;

assign rom_addr = A[14:0];
assign st_dout  = ram_dout;

// ---------------------------------------------------------------- decode del Z80
always @* begin
    rom_cs = !A[15] && !rd_n;                  // 0000-7fff
    ram_cs = 0;
    in0_cs = 0;
    in1_cs = 0;
    if( !mreq_n && rfsh_n && A[15] ) begin
        case( A[14:11] )
            4'b0001: in1_cs = 1;               // 8800
            4'b0011: in0_cs = 1;               // 9800
            4'b1000,
            4'b1001: ram_cs = 1;               // c000-c7ff  (c000-cfff decodificado sin mas)
            default:;                          // 9000 / a000: escrituras que se ignoran
        endcase
    end
end

always @(posedge clk) begin
    cpu_din <= rom_cs ? rom_data :
               ram_cs ? ram_dout :
               in0_cs ? cab_in0  :
               in1_cs ? cab_in1  :
               8'hff;
end

// ---------------------------------------------------------------- IRQ (vblank, irq0_line_hold)
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        int_n  <= 1;
        lvbl_l <= 0;
    end else begin
        lvbl_l <= LVBL;
        if( !LVBL && lvbl_l ) int_n <= 0;      // flanco de bajada de LVBL = empieza el vblank
        if( irq_ack )         int_n <= 1;      // la CPU la reconoce -> se suelta
    end
end

// ---------------------------------------------------------------- RAM compartida (2 KB)
// Puerto 0 = 68000 (indice de BYTE = A[11:1])   |   Puerto 1 = Z80 (A[10:0])
jtframe_dual_ram #(.AW(11)) u_shram(
    .clk0   ( clk            ),
    .data0  ( din            ),
    .addr0  ( addr           ),
    .we0    ( cs & ~rnw      ),
    .q0     ( dout           ),

    .clk1   ( clk            ),
    .data1  ( cpu_dout       ),
    .addr1  ( A[10:0]        ),
    .we1    ( ram_cs & ~wr_n ),
    .q1     ( ram_dout       )
);

// RAM_AW=1: el Z80 sustituto NO tiene RAM propia (su unica RAM es la COMPARTIDA, que manejamos
// aqui fuera con un dual_ram). Se deja el minimo para no gastar BRAM.
jtframe_sysz80 #(.RAM_AW(1),.RECOVERY(0)) u_cpu(
    .rst_n      ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen4      ),
    .cpu_cen    (           ),
    .int_n      ( int_n     ),
    .nmi_n      ( 1'b1      ),
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
    .cpu_din    ( cpu_din   ),
    .cpu_dout   ( cpu_dout  ),
    .ram_dout   (           ),
    .ram_cs     ( 1'b0      ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

endmodule
