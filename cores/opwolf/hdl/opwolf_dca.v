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

// TC0060DCA - control de volumen digital programable de Taito (2 canales).
// La curva NO es lineal ni logaritmica: es una SIGMOIDE medida sobre el chip real.
// De MAME (mame-src/taito/tc0060dca.cpp, "volume curve measured by Stephen Leary"):
//
//     atten[x] = 1.0 / (1.0 + exp(-10 * ((x / 256.0) - 0.6)))      x = 0..255
//
// Tabla precalculada a 8 bits (ganancia/256):  vol=0 -> 1 (~0.4%),  vol=255 -> 250 (~98%).
// El punto medio (0.5) cae en vol=153, no en 128: por eso una rampa lineal de volumen
// suena "tarde". Aplicar la ganancia como (muestra * gain) >>> 8.
//
// opwolf lleva DOS: DCA[0] atenua cada MSM5205 (su reg 5), DCA[1] es el volumen MAESTRO
// (Z80: 0xd000 = canal 1 / izq, 0xe000 = canal 2 / der).

module opwolf_dca(
    input             clk,
    input      [ 7:0] vol,      // valor escrito por el Z80
    output reg [ 7:0] gain      // ganancia en 1/256
);

always @(posedge clk) begin
    case( vol )
        8'd0  : gain <= 8'd1  ;
        8'd1  : gain <= 8'd1  ;
        8'd2  : gain <= 8'd1  ;
        8'd3  : gain <= 8'd1  ;
        8'd4  : gain <= 8'd1  ;
        8'd5  : gain <= 8'd1  ;
        8'd6  : gain <= 8'd1  ;
        8'd7  : gain <= 8'd1  ;
        8'd8  : gain <= 8'd1  ;
        8'd9  : gain <= 8'd1  ;
        8'd10 : gain <= 8'd1  ;
        8'd11 : gain <= 8'd1  ;
        8'd12 : gain <= 8'd1  ;
        8'd13 : gain <= 8'd1  ;
        8'd14 : gain <= 8'd1  ;
        8'd15 : gain <= 8'd1  ;
        8'd16 : gain <= 8'd1  ;
        8'd17 : gain <= 8'd1  ;
        8'd18 : gain <= 8'd1  ;
        8'd19 : gain <= 8'd1  ;
        8'd20 : gain <= 8'd1  ;
        8'd21 : gain <= 8'd1  ;
        8'd22 : gain <= 8'd1  ;
        8'd23 : gain <= 8'd2  ;
        8'd24 : gain <= 8'd2  ;
        8'd25 : gain <= 8'd2  ;
        8'd26 : gain <= 8'd2  ;
        8'd27 : gain <= 8'd2  ;
        8'd28 : gain <= 8'd2  ;
        8'd29 : gain <= 8'd2  ;
        8'd30 : gain <= 8'd2  ;
        8'd31 : gain <= 8'd2  ;
        8'd32 : gain <= 8'd2  ;
        8'd33 : gain <= 8'd2  ;
        8'd34 : gain <= 8'd2  ;
        8'd35 : gain <= 8'd2  ;
        8'd36 : gain <= 8'd3  ;
        8'd37 : gain <= 8'd3  ;
        8'd38 : gain <= 8'd3  ;
        8'd39 : gain <= 8'd3  ;
        8'd40 : gain <= 8'd3  ;
        8'd41 : gain <= 8'd3  ;
        8'd42 : gain <= 8'd3  ;
        8'd43 : gain <= 8'd3  ;
        8'd44 : gain <= 8'd3  ;
        8'd45 : gain <= 8'd4  ;
        8'd46 : gain <= 8'd4  ;
        8'd47 : gain <= 8'd4  ;
        8'd48 : gain <= 8'd4  ;
        8'd49 : gain <= 8'd4  ;
        8'd50 : gain <= 8'd4  ;
        8'd51 : gain <= 8'd5  ;
        8'd52 : gain <= 8'd5  ;
        8'd53 : gain <= 8'd5  ;
        8'd54 : gain <= 8'd5  ;
        8'd55 : gain <= 8'd5  ;
        8'd56 : gain <= 8'd6  ;
        8'd57 : gain <= 8'd6  ;
        8'd58 : gain <= 8'd6  ;
        8'd59 : gain <= 8'd6  ;
        8'd60 : gain <= 8'd6  ;
        8'd61 : gain <= 8'd7  ;
        8'd62 : gain <= 8'd7  ;
        8'd63 : gain <= 8'd7  ;
        8'd64 : gain <= 8'd7  ;
        8'd65 : gain <= 8'd8  ;
        8'd66 : gain <= 8'd8  ;
        8'd67 : gain <= 8'd8  ;
        8'd68 : gain <= 8'd9  ;
        8'd69 : gain <= 8'd9  ;
        8'd70 : gain <= 8'd9  ;
        8'd71 : gain <= 8'd10 ;
        8'd72 : gain <= 8'd10 ;
        8'd73 : gain <= 8'd10 ;
        8'd74 : gain <= 8'd11 ;
        8'd75 : gain <= 8'd11 ;
        8'd76 : gain <= 8'd12 ;
        8'd77 : gain <= 8'd12 ;
        8'd78 : gain <= 8'd13 ;
        8'd79 : gain <= 8'd13 ;
        8'd80 : gain <= 8'd14 ;
        8'd81 : gain <= 8'd14 ;
        8'd82 : gain <= 8'd15 ;
        8'd83 : gain <= 8'd15 ;
        8'd84 : gain <= 8'd16 ;
        8'd85 : gain <= 8'd16 ;
        8'd86 : gain <= 8'd17 ;
        8'd87 : gain <= 8'd18 ;
        8'd88 : gain <= 8'd18 ;
        8'd89 : gain <= 8'd19 ;
        8'd90 : gain <= 8'd20 ;
        8'd91 : gain <= 8'd20 ;
        8'd92 : gain <= 8'd21 ;
        8'd93 : gain <= 8'd22 ;
        8'd94 : gain <= 8'd23 ;
        8'd95 : gain <= 8'd23 ;
        8'd96 : gain <= 8'd24 ;
        8'd97 : gain <= 8'd25 ;
        8'd98 : gain <= 8'd26 ;
        8'd99 : gain <= 8'd27 ;
        8'd100: gain <= 8'd28 ;
        8'd101: gain <= 8'd29 ;
        8'd102: gain <= 8'd30 ;
        8'd103: gain <= 8'd31 ;
        8'd104: gain <= 8'd32 ;
        8'd105: gain <= 8'd33 ;
        8'd106: gain <= 8'd34 ;
        8'd107: gain <= 8'd36 ;
        8'd108: gain <= 8'd37 ;
        8'd109: gain <= 8'd38 ;
        8'd110: gain <= 8'd39 ;
        8'd111: gain <= 8'd41 ;
        8'd112: gain <= 8'd42 ;
        8'd113: gain <= 8'd43 ;
        8'd114: gain <= 8'd45 ;
        8'd115: gain <= 8'd46 ;
        8'd116: gain <= 8'd48 ;
        8'd117: gain <= 8'd49 ;
        8'd118: gain <= 8'd51 ;
        8'd119: gain <= 8'd52 ;
        8'd120: gain <= 8'd54 ;
        8'd121: gain <= 8'd56 ;
        8'd122: gain <= 8'd57 ;
        8'd123: gain <= 8'd59 ;
        8'd124: gain <= 8'd61 ;
        8'd125: gain <= 8'd63 ;
        8'd126: gain <= 8'd65 ;
        8'd127: gain <= 8'd67 ;
        8'd128: gain <= 8'd69 ;
        8'd129: gain <= 8'd71 ;
        8'd130: gain <= 8'd73 ;
        8'd131: gain <= 8'd75 ;
        8'd132: gain <= 8'd77 ;
        8'd133: gain <= 8'd79 ;
        8'd134: gain <= 8'd81 ;
        8'd135: gain <= 8'd83 ;
        8'd136: gain <= 8'd85 ;
        8'd137: gain <= 8'd88 ;
        8'd138: gain <= 8'd90 ;
        8'd139: gain <= 8'd92 ;
        8'd140: gain <= 8'd94 ;
        8'd141: gain <= 8'd97 ;
        8'd142: gain <= 8'd99 ;
        8'd143: gain <= 8'd101;
        8'd144: gain <= 8'd104;
        8'd145: gain <= 8'd106;
        8'd146: gain <= 8'd109;
        8'd147: gain <= 8'd111;
        8'd148: gain <= 8'd114;
        8'd149: gain <= 8'd116;
        8'd150: gain <= 8'd119;
        8'd151: gain <= 8'd121;
        8'd152: gain <= 8'd124;
        8'd153: gain <= 8'd126;
        8'd154: gain <= 8'd128;
        8'd155: gain <= 8'd131;
        8'd156: gain <= 8'd133;
        8'd157: gain <= 8'd136;
        8'd158: gain <= 8'd138;
        8'd159: gain <= 8'd141;
        8'd160: gain <= 8'd143;
        8'd161: gain <= 8'd146;
        8'd162: gain <= 8'd148;
        8'd163: gain <= 8'd151;
        8'd164: gain <= 8'd153;
        8'd165: gain <= 8'd155;
        8'd166: gain <= 8'd158;
        8'd167: gain <= 8'd160;
        8'd168: gain <= 8'd162;
        8'd169: gain <= 8'd165;
        8'd170: gain <= 8'd167;
        8'd171: gain <= 8'd169;
        8'd172: gain <= 8'd171;
        8'd173: gain <= 8'd174;
        8'd174: gain <= 8'd176;
        8'd175: gain <= 8'd178;
        8'd176: gain <= 8'd180;
        8'd177: gain <= 8'd182;
        8'd178: gain <= 8'd184;
        8'd179: gain <= 8'd186;
        8'd180: gain <= 8'd188;
        8'd181: gain <= 8'd190;
        8'd182: gain <= 8'd192;
        8'd183: gain <= 8'd194;
        8'd184: gain <= 8'd195;
        8'd185: gain <= 8'd197;
        8'd186: gain <= 8'd199;
        8'd187: gain <= 8'd201;
        8'd188: gain <= 8'd202;
        8'd189: gain <= 8'd204;
        8'd190: gain <= 8'd205;
        8'd191: gain <= 8'd207;
        8'd192: gain <= 8'd208;
        8'd193: gain <= 8'd210;
        8'd194: gain <= 8'd211;
        8'd195: gain <= 8'd213;
        8'd196: gain <= 8'd214;
        8'd197: gain <= 8'd215;
        8'd198: gain <= 8'd217;
        8'd199: gain <= 8'd218;
        8'd200: gain <= 8'd219;
        8'd201: gain <= 8'd220;
        8'd202: gain <= 8'd222;
        8'd203: gain <= 8'd223;
        8'd204: gain <= 8'd224;
        8'd205: gain <= 8'd225;
        8'd206: gain <= 8'd226;
        8'd207: gain <= 8'd227;
        8'd208: gain <= 8'd228;
        8'd209: gain <= 8'd229;
        8'd210: gain <= 8'd230;
        8'd211: gain <= 8'd231;
        8'd212: gain <= 8'd231;
        8'd213: gain <= 8'd232;
        8'd214: gain <= 8'd233;
        8'd215: gain <= 8'd234;
        8'd216: gain <= 8'd235;
        8'd217: gain <= 8'd235;
        8'd218: gain <= 8'd236;
        8'd219: gain <= 8'd237;
        8'd220: gain <= 8'd237;
        8'd221: gain <= 8'd238;
        8'd222: gain <= 8'd239;
        8'd223: gain <= 8'd239;
        8'd224: gain <= 8'd240;
        8'd225: gain <= 8'd240;
        8'd226: gain <= 8'd241;
        8'd227: gain <= 8'd241;
        8'd228: gain <= 8'd242;
        8'd229: gain <= 8'd242;
        8'd230: gain <= 8'd243;
        8'd231: gain <= 8'd243;
        8'd232: gain <= 8'd244;
        8'd233: gain <= 8'd244;
        8'd234: gain <= 8'd244;
        8'd235: gain <= 8'd245;
        8'd236: gain <= 8'd245;
        8'd237: gain <= 8'd246;
        8'd238: gain <= 8'd246;
        8'd239: gain <= 8'd246;
        8'd240: gain <= 8'd247;
        8'd241: gain <= 8'd247;
        8'd242: gain <= 8'd247;
        8'd243: gain <= 8'd247;
        8'd244: gain <= 8'd248;
        8'd245: gain <= 8'd248;
        8'd246: gain <= 8'd248;
        8'd247: gain <= 8'd249;
        8'd248: gain <= 8'd249;
        8'd249: gain <= 8'd249;
        8'd250: gain <= 8'd249;
        8'd251: gain <= 8'd249;
        8'd252: gain <= 8'd250;
        8'd253: gain <= 8'd250;
        8'd254: gain <= 8'd250;
        8'd255: gain <= 8'd250;
    endcase
end

endmodule
