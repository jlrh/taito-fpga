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

// PISTOLA OPTICA
//
// En el PCB real (esquematicos hoja 6-6) unas cadenas de 74LS161 cuentan el barrido (H1-H9, V1-V9) y,
// cuando el sensor optico ve el haz, unos 74LS373 los CONGELAN. El 68000 los lee en 0x3a0000 (X) y
// 0x3a0002 (Y), 9 bits cada uno.
//
// En MiSTer NO hay sensor optico: jtframe (JTFRAME_LIGHTGUN) ya nos da la posicion APUNTADA en
// coordenadas de PANTALLA (gun_1p_x 0..319, gun_1p_y 0..239) desde el raton/analogico. Asi que en vez
// de sintetizar el haz, se calcula el valor que el juego espera leer, que es el que MAME reproduce
// (opwolf.cpp: gun_x_r / gun_y_r):
//
//     gun_x = (P1X * 320/256) + 0x15 + XOFFS      con P1X*320/256 = coordenada X de pantalla
//     gun_y =  P1Y            - 0x24 + YOFFS      con P1Y = valor de 8 bits sobre el alto de pantalla
//
// Para Y hay que deshacer la escala: P1Y = y_pantalla * 256/240. Se aproxima con
// y + (y>>4) = y*1.0625 (frente a 1.0667): el error maximo es de 1 pixel en el borde inferior.
//
// ⚠ Los OFFSETS DEPENDEN DEL SET (opwolf.cpp, init_*):
//       opwolfb : XOFFS = -2, YOFFS = 17
//       opwolfp : XOFFS =  5, YOFFS = 30
//       opwolf  : se leen de la propia ROM (0x3ffb0 / 0x3ffae)
//   Ahora mismo se fijan por parametro y el core se compila con los de opwolfb (el set jugable
//   principal). TODO Fase 5: pasarlos por CABECERA de la .mra (JTFRAME_HEADER) para soportar los dos
//   sets con el mismo .rbf, y calibrar en HW.

module opwolf_gun #( parameter
    signed XOFFS = -2,      // opwolfb
    signed YOFFS = 17
)(
    input             rst,
    input             clk,
    input             pxl_cen,

    input             latch_en,   // spritectrl bit 4: habilita el latch en vblank
    input      [ 8:0] gun_1p_x,   // posicion apuntada (jtframe, coordenadas de PANTALLA)
    input      [ 8:0] gun_1p_y,

    output reg [ 8:0] gun_x,      // IN200-208 (0x3a0000)
    output reg [ 8:0] gun_y       // IN300-308 (0x3a0002)
);

// y * 256/240  ~=  y + (y>>4)
wire [ 9:0] y_scaled = {1'b0, gun_1p_y} + {5'd0, gun_1p_y[8:4]};

wire signed [10:0] x_raw = $signed({2'b0, gun_1p_x}) + 11'sd21 + XOFFS;   // 0x15
wire signed [10:0] y_raw = $signed({1'b0, y_scaled }) - 11'sd36 + YOFFS;  // 0x24

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        gun_x <= 9'd0;
        gun_y <= 9'd0;
    end else if( pxl_cen && latch_en ) begin
        // el 68000 lee 9 bits (mascara 0x1ff del driver)
        gun_x <= x_raw[8:0];
        gun_y <= y_raw[8:0];
    end
end

endmodule
