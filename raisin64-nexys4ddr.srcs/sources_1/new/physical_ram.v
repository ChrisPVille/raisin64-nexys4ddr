//We have configured the MIG in 2:1 mode to simplify the clocking 
//requirements. Note that the underlying transaction size is still 128-bits.
//In 2:1 mode, we are required to read and write our data across 2 cycles
//in 64-bit chunks. This can be done internal to the module so we still present 
//128-bit ports to the rest of the design.
//
//A happy side-effect of the 2:1 mode (vs 4:1 mode) is that ui_clk runs at
//double the speed, decreasing the delay of the clock domain crossing from the 
//CPU into the ui_*/app_* memory controller domain.

`include "io_def.vh"

module physical_ram(
    input clk_100mhz,
    input rst_n,
    
    inout[15:0] ddr2_dq,
    inout[1:0] ddr2_dqs_n,
    inout[1:0] ddr2_dqs_p,
    output[12:0] ddr2_addr,
    output[2:0] ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output[0:0] ddr2_ck_p,
    output[0:0] ddr2_ck_n,
    output[0:0] ddr2_cke,
    output[0:0] ddr2_cs_n,
    output[1:0] ddr2_dm,
    output[0:0] ddr2_odt,
    
    input cpu_clk,
    input[26:0] addr,
    input[1:0] width,
    input[127:0] data_in,
    output reg[127:0] data_out,
    input rstrobe,
    input wstrobe,
    output transaction_complete    
    );
    
    wire ui_clk, ui_clk_sync_rst;
    
    reg[2:0] mem_cmd;
    reg mem_en;
    wire mem_rdy;

    wire mem_rd_data_end, mem_rd_data_valid;
    wire[63:0] mem_rd_data;
    
    reg[63:0] mem_wdf_data;
    reg mem_wdf_end, mem_wdf_wren;
    reg[7:0] mem_wdf_mask;
    wire mem_wdf_rdy;

    mig mig1 (
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .init_calib_complete(),
      
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),

        .app_addr(addr),
        .app_cmd(mem_cmd),
        .app_en(mem_en),
        .app_wdf_data(mem_wdf_data),
        .app_wdf_end(mem_wdf_end),
        .app_wdf_wren(mem_wdf_wren),
        .app_rd_data(mem_rd_data),
        .app_rd_data_end(mem_rd_data_end),
        .app_rd_data_valid(mem_rd_data_valid),
        .app_rdy(mem_rdy),
        .app_wdf_rdy(mem_wdf_rdy),
        .app_sr_req(1'b0),
        .app_ref_req(1'b0),
        .app_zq_req(1'b0),
        .app_sr_active(),
        .app_ref_ack(),
        .app_zq_ack(),
        .ui_clk(ui_clk),
        .ui_clk_sync_rst(ui_clk_sync_rst),
      
        .app_wdf_mask(mem_wdf_mask),
      
        .sys_clk_i(clk_100mhz),
        .sys_rst(rst_n)
        );
    
    //Addresses and data remain stable from the initial strobe till the end of
    //the transaction. It is only necessary to synchronize the strobes.
    wire rstrobe_sync, wstrobe_sync;
    
    flag_sync rs_sync(
        .rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(rstrobe),
        .b_clk(ui_clk),
        .b_flag(rstrobe_sync)
        );
    
    flag_sync ws_sync(
        .rst_n(rst_n),
        .a_clk(cpu_clk),
        .a_flag(wstrobe),
        .b_clk(ui_clk),
        .b_flag(wstrobe_sync)
        );
        
    reg complete;

    flag_sync complete_sync(
        .rst_n(rst_n),
        .a_clk(ui_clk),
        .a_flag(complete),
        .b_clk(cpu_clk),
        .b_flag(transaction_complete)
        );
        
    reg[2:0] state;
    
    localparam STATE_IDLE = 3'h0;
    localparam STATE_READADDR = 3'h1;
    localparam STATE_WRITEADDR = 3'h4;
    localparam STATE_WRITEDATA_H = 3'h5;
    localparam STATE_WRITEDATA_L = 3'h6;
    
    localparam CMD_READ = 3'h1;
    localparam CMD_WRITE = 3'h0;
        
    //mem_rd_data becomes ready the same cycle as mem_rdy is asserted and
    //otherwise has no relationship with mem_rdy. mem_rd_data_valid is the
    //only authoritative trigger for registering read bytes.
    always @(posedge ui_clk or negedge rst_n) begin
        if(~rst_n) begin
            data_out <= 127'h0;
        end else if (state == STATE_READADDR && mem_rd_data_valid) begin   
            if(mem_rd_data_end) data_out[63:0] <= mem_rd_data;
            else data_out[127:64] <= mem_rd_data;
        end
    end
    
    //The Command and Write Data queues are independent 
    always @(posedge ui_clk or negedge rst_n) begin
        if(~rst_n) begin
            state <= STATE_IDLE;
            complete <= 0;
            mem_cmd <= CMD_WRITE;
            mem_wdf_mask <= 8'h00;
            mem_wdf_data <= 64'h0;
            mem_wdf_wren <= 0;
            mem_wdf_end <= 0;
            mem_en <= 0;
        end else begin
            complete <= 0;
                            
            case(state)
            
            STATE_IDLE: begin
                mem_wdf_wren <= 0;   
                if(wstrobe_sync) begin
                    mem_en <= 1;
                    mem_cmd <= CMD_WRITE;
                    mem_wdf_end <= 0;
                    state <= STATE_WRITEADDR;
                end 
                else if(rstrobe_sync) begin
                    mem_en <= 1;
                    mem_cmd <= CMD_READ;
                    state <= STATE_READADDR;
                end
            end

            STATE_WRITEDATA_H: begin
                if(mem_wdf_rdy) begin //Wait for Write Data queue to have space
                    //TODO Temporary masking until we have full 128-bits from cache eviction
                    case(width)
                    `RAM_WIDTH64: begin
                        mem_wdf_mask <= 8'h00; mem_wdf_data <= data_in[63:0];
                    end
                    `RAM_WIDTH32: begin
                        mem_wdf_mask <= 8'hF0;
                        mem_wdf_data <= {data_in[63:32],data_in[63:32]};
                    end
                    `RAM_WIDTH16: begin
                    mem_wdf_mask <= 8'hFC;
                    mem_wdf_data <= {data_in[63:48],data_in[63:48],data_in[63:48],data_in[63:48]};
                    end
                    `RAM_WIDTH8: begin
                    mem_wdf_mask <= 8'hFE;
                    mem_wdf_data <= {data_in[63:56],data_in[63:56],data_in[63:56],data_in[63:56],data_in[63:56],data_in[63:56],data_in[63:56],data_in[63:56]};
                    end
                    endcase
                    mem_wdf_mask <= 8'hFF; //TODO unmask when plugged into cache
                    mem_wdf_wren <= 1;
                    state <= STATE_WRITEDATA_L;
                end
            end
            
            STATE_WRITEDATA_L: begin
                if(mem_wdf_rdy) begin //Wait for Write Data queue to have space 
                    mem_wdf_mask <= 8'hFF;
                    mem_wdf_data <= 64'h0;
                    mem_wdf_wren <= 1;
                    mem_wdf_end <= 1;
                    complete <= 1;
                    state <= STATE_IDLE;
                end
            end
            
            STATE_READADDR: begin
                if(mem_rdy) begin //Wait for command queue to accept command 
                    mem_en <= 0;   
                    if(mem_rd_data_valid & mem_rd_data_end) begin
                        state <= STATE_IDLE;
                        complete <= 1;
                    end
                end
            end
            
            STATE_WRITEADDR: begin
                if(mem_rdy) begin //Wait for command queue to accept command
                    mem_en <= 0;   
                    state <= STATE_WRITEDATA_H;
                end
            end
            endcase
        end
    end

endmodule
