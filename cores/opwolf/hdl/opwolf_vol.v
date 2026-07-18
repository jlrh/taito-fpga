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

// Aplica DOS ganancias en cascada (la del canal y la maestra) a una muestra con signo.
// Las ganancias vienen del opwolf_dca (TC0060DCA) en formato 1/256.
//   sout = (sin * gain * gmaster) >>> 16
// Registrado en dos etapas para no meter dos multiplicadores en serie en el path critico.

module opwolf_vol #( parameter DW=12 )(
    input                    clk,
    input      [ 7:0]        gain,      // ganancia del canal   (TC0060DCA[0])
    input      [ 7:0]        gmaster,   // ganancia maestra     (TC0060DCA[1])
    input  signed [DW-1:0]   sin,
    output signed [DW-1:0]   sout
);

reg signed [DW+8-1:0] st1;
reg signed [DW+8-1:0] st2;

always @(posedge clk) begin
    // etapa 1: ganancia del canal
    st1 <= (sin * $signed({1'b0, gain})) >>> 8;
    // etapa 2: ganancia maestra
    st2 <= (st1 * $signed({1'b0, gmaster})) >>> 8;
end

assign sout = st2[DW-1:0];

endmodule
