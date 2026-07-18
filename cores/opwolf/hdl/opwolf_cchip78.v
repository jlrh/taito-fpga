/*  This file is part of JTCORES. GPLv3.
    Operation Wolf (Taito, 1987) - core FPGA

    C-CHIP REAL (Taito TC0030CMD) — LLE con el core uPD78C11 (upd7810.v).
    Esto es lo que DESBLOQUEA EL SET ORIGINAL 'opwolf'. Ver research/CCHIP-LLE-PLAN.md.

    Diferencia con opwolf_cchip.v (el del bootleg): aquel corre un Z80 con la HLE que
    escribieron los bootleggers, y su 68000 esta PARCHEADO. Aqui corren LAS ROM REALES del
    chip, asi que sirve para el 68000 ORIGINAL.

    ============================================================================================
    MAPA (de mame-src/taito/taitocchip.cpp)
    ============================================================================================
    Lo que ve la CPU del C-Chip:
      0x0000-0x0FFF  ROM INTERNA del uPD78C11 (4K)   -- bootstrap comun de los C-Chip de Taito
      0x1000-0x13FF  ventana de 1K sobre la SRAM de 8K   (banco = reg ASIC 0x1600, 3 bits)
      0x1400-0x17FF  registros ASIC:  offset<0x200 -> asic_ram[offset&3]
                                      offset==0x200 -> SELECTOR DE BANCO (lado CPU)
      0x2000-0x3FFF  EPROM EXTERNA (8K)              -- el codigo especifico de Operation Wolf
      0xFF00-0xFFFF  RAM interna del 78C11 (256 B)   -- el direccionamiento 'wa' apunta aqui

    Lo que ve el 68000 (0x0f0000):
      0x0f0000-0x0f07ff  la MISMA ventana de 1K de la SRAM ... pero con SU PROPIO banco
      0x0f0800-0x0f0fff  registros ASIC del lado 68k (mismos 4 bytes + su selector de banco)

    ⚠⚠ LOS DOS LADOS TIENEN REGISTROS DE BANCO SEPARADOS (bank / bank68). Confundirlos es el
       error obvio: cada uno ve una ventana distinta de los mismos 8 KB.
    ⚠  UNA PALABRA del 68000 = UN BYTE de la SRAM (umask16 0x00ff) -> el indice es A[10:1].
    ⚠  Los 4 bytes de 'asic_ram' son COMPARTIDOS por los dos lados: son el buzon de comandos.
       El 68000 escribe el comando en 0x0f0802 y el C-Chip lo lee en 0x1401.

    ============================================================================================
    LATENCIA (esto ya me mordio una vez, ver GOTCHAS §H22 y el TB del core)
    ============================================================================================
    upd7810 pone 'addr' en un pulso de cen y espera el dato EN EL SIGUIENTE. Las BRAM van a
    'clk' COMPLETO y el cen del C-Chip es < 1/2 (12 MHz sobre 26.686) -> entre dos pulsos de cen
    hay >=2 flancos de clk, asi que la BRAM SIEMPRE llega a tiempo. Si alguna vez subes el cen a
    >=1/2, el core leeria EL PROPIO OPCODE COMO OPERANDO.
*/

module opwolf_cchip78(
    input             rst,
    input             clk,
    input             cen12,       // 12 MHz (XTAL3 del esquematico)

    // ---- lado 68000
    input      [11:1] addr,
    input      [ 7:0] din,
    output reg [ 7:0] dout,
    input             cs,          // 0x0f0000-0x0f0fff (⚠ INCLUYE el ASIC: hay que excluirlo)
    input             asic_cs,     // 0x0f0800-0x0f0fff : registros ASIC
    input             rnw,

    // ---- ROM del C-Chip (BRAM de 16K cargada por PROM desde la .mra)
    //      0x0000-0x0FFF = ROM interna  |  0x2000-0x3FFF = EPROM externa
    output     [13:0] rom_addr,
    input      [ 7:0] rom_data,

    input             LVBL,        // vblank -> INTF1

    // inputs de cabina: en el PCB real ENTRAN POR LOS PUERTOS DEL C-CHIP, no por el bus del 68k
    input      [ 7:0] cab_in0,     // -> PB : monedas
    input      [ 7:0] cab_in1,     // -> PC : gatillo, granada, service, tilt, start

    output     [ 7:0] st_dout,     // debug
    output            undef,       // opcode NO implementado (para el sim)

    // ---- TELEMETRIA DE PLACA (síntesis) para diagnosticar el gatillo pillado.
    //   El firmware escribe el byte de botones (que el 68000 lee) en la SRAM offset 0x1005.
    //   Con estos contadores LATCHEADOS se lee EN PLACA (tras el pillado, sin prisa) si el C-Chip
    //   sigue corriendo el código y si el valor cambia. Ver research/BEAR-VS-WOLF.md §7.
    output reg [ 7:0] dbg_r1005,    // último valor escrito a 0x1005 (byte de botones -> 68000)
    output reg [ 7:0] dbg_wr1005,   // nº de ESCRITURAS a 0x1005 (¿corre el código de forwarding?)
    output reg [ 7:0] dbg_ch1005,   // nº de escrituras a 0x1005 con valor DISTINTO (¿el valor cambia?)
    output reg [ 7:0] dbg_instr,    // heartbeat por instrucción (¿el C-Chip está VIVO?)
    output     [15:0] dbg_pc        // PC actual del C-Chip (¿atascado en un bucle?)
);

// ---------------------------------------------------------------- CPU
wire [15:0] cpu_addr;
wire [ 7:0] cpu_dout;
wire        cpu_we;
reg  [ 7:0] cpu_din;
wire [ 7:0] pb_out;
wire        trace_stb;
wire [15:0] trace_pc;

// ⚠ 'cchip_cs' del decodificador cubre 0f0000-0f0fff ENTERO (el ASIC incluido). La ventana de
//   la SRAM es solo la mitad baja: sin esta puerta, escribir un registro ASIC tambien machacaria
//   la RAM compartida.
wire mem_cs = cs & ~addr[11];

// ---------------------------------------------------------------- memoria interna
reg  [ 2:0] bank, bank68;          // ⚠ DOS bancos distintos
reg  [ 7:0] asic_ram[0:3];
wire [ 7:0] sram_cpu, sram_68k, iram_dout;
reg         intf1, lvbl_l;

// decodificacion del lado CPU
wire cpu_rom  = cpu_addr <  16'h1000 || (cpu_addr >= 16'h2000 && cpu_addr < 16'h4000);
wire cpu_sram = cpu_addr >= 16'h1000 && cpu_addr < 16'h1400;
wire cpu_asic = cpu_addr >= 16'h1400 && cpu_addr < 16'h1800;
wire cpu_iram = cpu_addr >= 16'hff00;
// offset dentro de la zona ASIC (0..0x3ff). 0x200 = selector de banco.
wire [9:0] asic_off = cpu_addr[9:0];
wire       cpu_bank_we = cpu_asic & cpu_we & (asic_off==10'h200);

assign rom_addr = cpu_addr[13:0];
assign st_dout  = {5'd0, bank};

// mux de lectura de la CPU. Las BRAM ya tienen el dato listo (ver nota de LATENCIA arriba).
always @* begin
    cpu_din = 8'hff;
    if( cpu_rom  ) cpu_din = rom_data;
    if( cpu_sram ) cpu_din = sram_cpu;
    if( cpu_iram ) cpu_din = iram_dout;
    if( cpu_asic ) cpu_din = asic_off < 10'h200 ? asic_ram[cpu_addr[1:0]] : 8'h00;
end

// ---------------------------------------------------------------- registros ASIC y bancos
// Los escriben LOS DOS lados. Es el buzon de comandos entre el 68000 y el C-Chip.
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        bank   <= 0;
        bank68 <= 0;
        asic_ram[0] <= 0; asic_ram[1] <= 0; asic_ram[2] <= 0; asic_ram[3] <= 0;
    end else begin
        // lado CPU
        if( cpu_asic && cpu_we ) begin
            if( asic_off==10'h200 ) bank <= cpu_dout[2:0];
            else                    asic_ram[cpu_addr[1:0]] <= cpu_dout;
        end
        // lado 68000  (offset de PALABRA = addr[10:1]; el selector de banco esta en 0x200)
        if( asic_cs && !rnw ) begin
            if( addr[10:1]==10'h200 ) bank68 <= din[2:0];
            else                      asic_ram[addr[2:1]] <= din;
        end
    end
end

// ---------------------------------------------------------------- lectura del 68000
// ⚠ COMBINACIONAL, NO registrada. La q0 de la BRAM YA lleva un ciclo; meter otro registro aqui
//   le da al 68000 el dato VIEJO (y no hay dtack que lo espere: dtackn=0). Sintoma exacto:
//   el auto-test del original imprime "C CHIP NOT RESPONSE !".
always @* begin
    dout = asic_cs ? (addr[10:1] < 10'h200 ? asic_ram[addr[2:1]] : 8'h00)
                   : sram_68k;
end

// ---------------------------------------------------------------- telemetria de simulacion
// El dialogo entre los dos procesadores es TODO lo que importa aqui. Si no lo ves, estas ciego:
//   el C-Chip escribe 0x01 en 0x1401 cuando acaba su auto-test ("estoy listo") y el 68000 lo
//   lee; si no llega, el original imprime "C CHIP NOT RESPONSE !".
`ifdef SIMULATION
integer cpu_instr=0, instr_win=0, cen_cnt=0;
reg [7:0] pb_out_l=8'hff;   // DEBUG: valor anterior de PB out (deteccion de pulsos de contador)
reg [7:0] cab1_l=8'hff;     // DEBUG: valor anterior de cab_in1 (=pc_in: gatillo/granada/start)
reg trace_stb_l=0;          // ⚠ trace_stb dura ~clk/cen (~2.22) pulsos: sin flanco se cuenta 2.22x
always @(posedge clk) begin
    trace_stb_l <= trace_stb;
    // DEBUG gatillo: el input crudo que entra al C-Chip por PC. Debe reflejar los toggles inyectados.
    cab1_l <= cab_in1;
    if( cab1_l !== cab_in1 )
        $display("%9t IN1(pc_in) %02X -> %02X  (b0=gatillo b1=granada b4=start, activos BAJO)",
                 $time, cab1_l, cab_in1);
    // 1 conteo POR INSTRUCCION: flanco de subida de trace_stb (no nivel; el nivel infla ~2.22x el
    //   ritmo porque trace_stb sigue alto entre dos pulsos de cen). El medidor por NIVEL hacia creer
    //   que el C-Chip iba 2.22x rapido cuando el cycle-timing (used/want) es correcto. Ver CYCDBG.
    if( trace_stb & ~trace_stb_l ) begin
        cpu_instr  <= cpu_instr+1;
        instr_win  <= instr_win+1;    // instrucciones en la ventana de medida actual
        // las primeras instrucciones deben ser: 0000 01E5 01E6 01E9 ... (igual que en MAME)
        if( cpu_instr < 12 ) $display("CCHIP PC[%0d]=%04X  rom_addr=%04X rom_data=%02X cpu_din=%02X",
                                       cpu_instr, trace_pc, rom_addr, rom_data, cpu_din);
    end
    // ⭐ MIDE el RITMO DE INSTRUCCIONES por VENTANA FIJA de 200000 pulsos de cen12 (= 1 frame de
    //   12MHz@60Hz). Se hace por cuenta de cen12, NO por vblank: el C-Chip puede rebootear en el
    //   attract y eso corromperia un conteo entre vblanks. MAME ejecuta ~6645 instr/frame; si el RTL
    //   hace muchas mas, la CPU va demasiado rapida y el rebote de entradas cuenta de mas.
    if( cen12 ) begin
        cen_cnt <= cen_cnt+1;
        if( cen_cnt == 200000-1 ) begin
            $display("CCHIP RITMO: %0d instrucciones / 200000 cen12 (MAME ~6645) -> cen/instr=%0d",
                     instr_win, instr_win>0 ? 200000/instr_win : 0);
            cen_cnt   <= 0;
            instr_win <= 0;
        end
    end
    // DEBUG contador de monedas: PB out bit4 (0x10) = coin counter 0 (pulso activo bajo por moneda).
    //   MAME: 1 pulso por moneda. Varios pulsos por UNA moneda = sobre-sensibilidad (el bug).
    pb_out_l <= pb_out;
    if( pb_out_l[4] && !pb_out[4] )
        $display("%9t *** COIN-COUNTER PULSE (PB[4] 1->0)  pb_out=%02X ***", $time, pb_out);
    if( pb_out_l !== pb_out )
        $display("%9t PB_out %02X -> %02X", $time, pb_out_l, pb_out);
    // DEBUG: valor CRUDO de moneda/botones que el C-Chip pasa al 68000 (0x1004/0x1005).
    //   Debe reflejar limpio "moneda presente -> ausente"; si fluctua -> el 68000 cuenta varios creditos.
    if( cpu_sram && cpu_we && cpu_addr==16'h1004 )
        $display("%9t CCHIP -> RAM[1004] = %02X  (PB/monedas cruda)", $time, cpu_dout);
    if( cpu_sram && cpu_we && cpu_addr==16'h1005 )
        $display("%9t CCHIP -> RAM[1005] = %02X  (PC/botones cruda)", $time, cpu_dout);
    // ⚠ Estos 3 son ALTA FRECUENCIA (el 68000 SONDEA el ASIC en cada poll del handshake): inflan el
    //   log ~100x y asfixian el sim por I/O. Off por defecto; enciende con -d CCHIP_ASIC_VERBOSE.
`ifdef CCHIP_ASIC_VERBOSE
    if( cpu_asic && cpu_we )
        $display("%9t CCHIP -> ASIC[%0d] = %02X   (bank=%0d)", $time, cpu_addr[1:0], cpu_dout, bank);
    if( asic_cs && !rnw )
        $display("%9t 68000 -> ASIC off=%03X = %02X", $time, addr[10:1], din);
    if( asic_cs &&  rnw )
        $display("%9t 68000 <- ASIC off=%03X = %02X", $time, addr[10:1], dout);
`endif
end

// ---------------------------------------------------------------- ⭐ TRAMPA DE FUGA DEL PC
// El bug de entradas en placa es una FUGA DEL PC (BEAR-VS-WOLF §9, GOTCHAS §I7): el PC salta FUERA
// del rango de codigo (medido en placa: PC=0xD925), ninguna zona del decoder matchea -> cpu_din
// coge el DEFAULT 8'hff -> y 0xFF en el uPD7810 es JR -1 -> SALTA A SI MISMA -> bucle infinito de
// UNA instruccion a toda velocidad. Sintoma: heartbeat sano pero el C-Chip no vuelve a refrescar
// RAM[1005] -> mueren gatillo+granada+coin+start a la vez.
//
// El JR -1 es la CUNETA, no el culpable. Esta trampa caza la INSTRUCCION CULPABLE: guarda un anillo
// con los ultimos PCLOG PCs validos y, en cuanto el PC se sale, los vuelca junto al SP y para el sim.
// La ULTIMA entrada del anillo = la instruccion que corrompio el PC. Desensamblar la ROM ahi.
//   -> sospechoso #1: retorno de interrupcion (pila mal restaurada -> RET/RETI saca basura).
localparam PCLOG = 48;
reg  [15:0] pclog[0:PCLOG-1];
integer     pcw=0, k;
reg         runaway_done=0;
// rango VALIDO de codigo = el mismo que cpu_rom (0x0000-0x0FFF y 0x2000-0x3FFF)
wire pc_valid = trace_pc < 16'h1000 || (trace_pc >= 16'h2000 && trace_pc < 16'h4000);

always @(posedge clk) begin
    if( rst ) begin
        pcw <= 0; runaway_done <= 0;
    end else if( trace_stb & ~trace_stb_l ) begin   // 1 por instruccion (FLANCO, ver §I8)
        if( pc_valid ) begin
            pclog[pcw] <= trace_pc;
            pcw        <= (pcw+1) % PCLOG;
        end else if( !runaway_done ) begin
            runaway_done <= 1;
            $display("\n*****************************************************************");
            $display("*** PC RUNAWAY: PC=%04X esta FUERA del rango de codigo         ***", trace_pc);
            $display("***   (valido: 0x0000-0x0FFF y 0x2000-0x3FFF)                  ***");
            $display("*****************************************************************");
            $display("  t=%0t   instruccion nº %0d   SP=%04X   cpu_din(leido en la fuga)=%02X",
                     $time, cpu_instr, u_cpu.sp, cpu_din);
            $display("  cab_in0(monedas)=%02X  cab_in1(gatillo/granada/start)=%02X  intf1=%b",
                     cab_in0, cab_in1, intf1);
            $display("  --- ULTIMOS %0d PCs VALIDOS (el ULTIMO es LA CULPABLE) ---", PCLOG);
            for( k=0; k<PCLOG; k=k+1 )
                $display("    [%2d] PC=%04X", k, pclog[(pcw+k) % PCLOG]);
            // La pila del uPD78C11 vive en la iram interna (0xFF00-0xFFFF) -> instancia u_iram de
            // ESTE modulo (no de u_cpu). Si el RET/RETI saca basura, el 25/D9 se vera aqui.
            $display("  --- PILA alrededor del SP (iram 0xFF00-0xFFFF) ---");
            for( k=-4; k<=8; k=k+1 )
                if( ((u_cpu.sp+k) & 16'hff00) == 16'hff00 )
                    $display("    %s ff%02X = %02X", (k==0)?"SP->":"    ",
                             (u_cpu.sp+k) & 8'hff, u_iram.mem[(u_cpu.sp+k) & 8'hff]);
            $finish;
        end
    end
end
`endif

// ---------------------------------------------------------------- INTF1 (vblank del 68000)
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        intf1 <= 0; lvbl_l <= 0;
    end else begin
        lvbl_l <= LVBL;
        intf1  <= !LVBL && lvbl_l;      // pulso en el flanco de bajada
    end
end

// ---------------------------------------------------------------- SRAM de 8 KB (doble puerto)
// Puerto 0 = 68000 : {bank68, A[10:1]}      |      Puerto 1 = C-Chip : {bank, A[9:0]}
jtframe_dual_ram #(.AW(13)) u_sram(
    .clk0   ( clk                   ),
    .data0  ( din                   ),
    .addr0  ( {bank68, addr[10:1]}  ),
    .we0    ( mem_cs & ~rnw         ),
    .q0     ( sram_68k              ),

    .clk1   ( clk                   ),
    .data1  ( cpu_dout              ),
    .addr1  ( {bank, cpu_addr[9:0]} ),
    .we1    ( cpu_sram & cpu_we     ),
    .q1     ( sram_cpu              )
);

// ---------------------------------------------------------------- RAM interna del 78C11 (256 B)
jtframe_ram #(.AW(8)) u_iram(
    .clk    ( clk               ),
    .cen    ( 1'b1              ),
    .data   ( cpu_dout          ),
    .addr   ( cpu_addr[7:0]     ),
    .we     ( cpu_iram & cpu_we ),
    .q      ( iram_dout         )
);

// ---------------------------------------------------------------- el uPD78C11
upd7810 u_cpu(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .cen        ( cen12     ),
    .addr       ( cpu_addr  ),
    .dout       ( cpu_dout  ),
    .we         ( cpu_we    ),
    .din        ( cpu_din   ),
    .pa_in      ( 8'hff     ),
    .pb_in      ( cab_in0   ),      // PB = IN0 (monedas)
    .pc_in      ( cab_in1   ),      // PC = IN1 (gatillo/start/service/tilt)
    .pa_out     (           ),
    .pb_out     ( pb_out    ),      // contadores de monedas (no se usan)
    .pc_out     (           ),
    .intf1      ( intf1     ),
    .trace_stb  ( trace_stb ),
    .trace_pc   ( trace_pc  ),
    .undef      ( undef     )
);

// ---------------------------------------------------------------- TELEMETRIA DE PLACA (síntesis)
// Contadores LATCHEADOS para leer en placa (OSD debug_view) tras el pillado del gatillo, SIN prisa
// (el pillado es un estado persistente). Diagnostican dónde se rompe la cadena de forwarding del input.
assign dbg_pc = trace_pc;
reg trace_stb_s = 0;
reg [7:0] r1005_prev = 8'hff;
always @(posedge clk, posedge rst) begin
    if( rst ) begin
        dbg_r1005 <= 8'hff; dbg_wr1005 <= 8'd0; dbg_ch1005 <= 8'd0; dbg_instr <= 8'd0;
        trace_stb_s <= 1'b0; r1005_prev <= 8'hff;
    end else begin
        trace_stb_s <= trace_stb;
        if( trace_stb & ~trace_stb_s ) dbg_instr <= dbg_instr + 8'd1;      // 1 por instrucción (¿vivo?)
        if( cpu_sram && cpu_we && cpu_addr==16'h1005 ) begin               // escritura del byte de botones
            dbg_r1005  <= cpu_dout;
            dbg_wr1005 <= dbg_wr1005 + 8'd1;                               // ¿corre el código del write?
            if( cpu_dout != r1005_prev ) begin
                dbg_ch1005 <= dbg_ch1005 + 8'd1;                           // ¿el valor CAMBIA?
                r1005_prev <= cpu_dout;
            end
        end
    end
end

endmodule
