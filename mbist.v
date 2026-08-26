`define ADDR_W 10
`define DATA_W 32

module mbist (
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    
    output wire               done,
    output wire               fail,
    output wire [`ADDR_W-1:0] fail_addr,
    
    output wire               mem_ce,    
    output wire               mem_we,    
    output wire [`ADDR_W-1:0] mem_addr,
    output wire [`DATA_W-1:0] mem_wdata,
    input  wire [`DATA_W-1:0] mem_rdata
);

    localparam [2:0] S_IDLE = 3'h0, 
                     S_M0   = 3'h1, // ^(w0, r0)
                     S_M1   = 3'h2, // ^(r0, w1, r1)
                     S_M2   = 3'h3, // ^(r1, w0, r0)
                     S_DONE = 3'h4;

    reg [2:0] state;
    reg [1:0] step;
    reg [`ADDR_W-1:0] addr;

    wire [1:0] max_step = (state == S_M0) ? 2'd1 :
                          (state == S_M1 || state == S_M2) ? 2'd2 : 
                          2'd0;

    wire step_done = (step == max_step);
    
    wire addr_done = (addr == {`ADDR_W{1'b1}});

    wire [`ADDR_W-1:0] next_addr = 
        (state == S_IDLE)              ? {`ADDR_W{1'b0}} :
        (state == S_M0 || 
         state == S_M1 || 
         state == S_M2 ) && step_done  ? addr + 1'b1     : addr;    // {width{1}} + 1 = 0;

    wire [2:0] next_state = 
        (state == S_IDLE && start)                ? S_M0 :
        (state == S_M0 && step_done && addr_done) ? S_M1 :
        (state == S_M1 && step_done && addr_done) ? S_M2 :
        (state == S_M2 && step_done && addr_done) ? S_DONE : state;


    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            step  <= 2'd0;
            addr  <= {`ADDR_W{1'b0}};
        end else begin
            state <= next_state;
            addr  <= next_addr;
            step  <= (state == S_IDLE || step_done) ? 2'd0 :
                     step + 1'b1;
        end
    end
    
    assign mem_ce   =  (state == S_M0 | 
                        state == S_M1 | 
                        state == S_M2);

    assign mem_we   =  (state == S_M1 | state == S_M2) & step == 2'd1 |
                                       (state == S_M0) & step == 2'd0 ;
    assign mem_addr = addr;

    assign mem_wdata = {`DATA_W{state == S_M1}}; 

    // Формирование эталонного бита для проверки прочитанных данных
    wire exp_bit = (state == S_M1 & step == 2'd2 || state == S_M2 & step == 2'd0);

    // Анализатор отклика //
    reg check_en;
    reg [`DATA_W-1:0] expected_data;
    reg fail_reg;
    reg [`ADDR_W-1:0] fail_addr_reg;

    always @(posedge clk) begin
        if (rst) begin
            check_en      <= 1'b0;
            expected_data <= {`DATA_W{1'b0}};
            fail_reg      <= 1'b0;
            fail_addr_reg <= {`ADDR_W{1'b0}};
        end else begin
            check_en      <= mem_ce & !mem_we; // Активация проверки данных, если в прошлом такте было чтение
            expected_data <= {`DATA_W{exp_bit}};
            fail_reg      <= (check_en && (mem_rdata != expected_data)) ? 1'b1 : fail_reg;
            fail_addr_reg <= (check_en && (mem_rdata != expected_data)) ? addr : fail_addr_reg;
        end
    end

    assign fail = fail_reg;
    assign fail_addr = fail_addr_reg;
    assign done = (state == S_DONE);

endmodule