module raisin64_nexys4_ddr_top(
    input CLK100MHZ,
    input CPU_RESETN,
    input[15:0] SW,
    output[15:0] LED,
    inout[8:1] JB
    );

    defparam cpu.imem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/imem.hex";
    defparam cpu.dmem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/dmem.hex";
    
    wire clk_dig;
    
    clk_synth pll(
        .clk_in(CLK100MHZ),
        .clk_dig(clk_dig)
        );
    
    raisin64 cpu(
        .clk(clk_dig),
        .rst_n(CPU_RESETN),
        .jtag_tck(JB[4]),
        .jtag_tms(JB[1]),
        .jtag_tdi(JB[2]),
        .jtag_trst(JB[7]),
        .jtag_tdo(JB[3])
        );

endmodule
