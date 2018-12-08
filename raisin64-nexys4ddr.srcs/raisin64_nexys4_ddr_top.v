module raisin64_nexys4_ddr_top(
    input CLK100MHZ,
    input CPU_RESETN,
    input[15:0] SW,
    output[15:0] LED,
    inout[8:1] JB
    );

    defparam cpu.imem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/imem.hex";
    defparam cpu.dmem.INIT_FILE = "/home/christopher/git/raisin64-cpu/support/dmem.hex";
    
    //////////  Clock Generation  //////////
    wire clk_dig;
    
    clk_synth pll(
        .clk_in(CLK100MHZ),
        .clk_dig(clk_dig)
        );

    //////////  Reset Sync/Stretch  //////////
    reg[31:0] rst_stretch = 32'hFFFFFFFF;
    wire rst_n;
    always @(posedge clk_dig) rst_stretch = {CPU_RESETN,rst_stretch[31:1]};
    assign rst_n = |rst_stretch[29:0]; //Ignore the top bits as they are not synchronized

    //////////  CPU  //////////
    wire[63:0] mem_from_cpu;
    wire[63:0] mem_to_cpu;
    wire[63:0] mem_addr;
    wire mem_addr_valid;
    wire mem_from_cpu_write;
    wire mem_to_cpu_ready;

    raisin64 cpu(
        .clk(clk_dig),
        .rst_n(rst_n),
        .mem_din(mem_to_cpu),
        .mem_dout(mem_from_cpu),
        .mem_addr(mem_addr),
        .mem_addr_valid(mem_addr_valid),
        .mem_dout_write(mem_from_cpu_write),
        .mem_din_ready(mem_to_cpu_ready),
        .jtag_tck(JB[4]),
        .jtag_tms(JB[1]),
        .jtag_tdi(JB[2]),
        .jtag_trst(JB[7]),
        .jtag_tdo(JB[3])
        );

    //////////  IO  //////////
    wire led_en, sw_en, vga_en;
    memory_map memory_map_external(
        .addr(mem_addr_valid ? mem_addr : 64'h0),
        .led(led_en),
        .sw(sw_en),
        .vga(vga_en)
        );

    //As noted in raisin64.v because our IO architecture will need to be completely
    //re-written with the introduction of caches, we only support 64-bit aligned
    //access to IO space for now.
    reg[15:0] led_reg;
    always @(posedge clk_dig or negedge rst_n) begin
        if(~rst_n) led_reg <= 16'h0;
        else if(led_en & mem_addr_valid & mem_from_cpu_write) led_reg <= mem_from_cpu;
    end

    assign LED = led_reg;

    //SW uses a small synchronizer
    reg[15:0] sw_pre0, sw_pre1;
    always @(posedge clk_dig or negedge rst_n) begin
        if(~rst_n) begin
            sw_pre0 <= 16'h0;
            sw_pre1 <= 16'h0;
        end else begin
            sw_pre0 <= sw_pre1;
            sw_pre1 <= SW;
        end
    end

    //Data selection
    assign mem_to_cpu_ready = mem_addr_valid;
    assign mem_to_cpu = sw_en ? sw_pre0 :
                        64'h0;

endmodule
