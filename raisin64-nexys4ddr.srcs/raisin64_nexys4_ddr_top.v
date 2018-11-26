module raisin64_nexys4_ddr_top(
    input CLK100MHZ,
    input CPU_RESETN,
    input  [15:0] SW,
    output [15:0] LED,
    inout  [8:1] JB,
    );

    raisin64 cpu(
        .clk(CLK100MHZ),
        .rst_n(CPU_RESETN),
        .jtag_tck(JB[4]),
        .jtag_tms(JB[1]),
        .jtag_tdi(JB[3]),
        .jtag_trst(JB[2]),
        .jtag_tdo(JB[7])
        );

endmodule
