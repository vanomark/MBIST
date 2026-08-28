module mbist #(
    parameter DEPTH  = 1000,
    parameter DATA_W = 32,
    parameter ADDR_W = $clog2(DEPTH)
)(
//========= CONNECTION WITH CONTROLLER =======//
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    
    output wire               done,
    output wire               fail,
    output wire [ADDR_W-1:0]  fail_addr,
    output wire [DATA_W-1:0]  fail_addr_mask,
//=============================================//

//========== CONNECTION WITH MEMORY ===========//
    output wire               mem_ce,    
    output wire               mem_we,    
    output wire [ADDR_W-1:0]  mem_addr,
    output wire [DATA_W-1:0]  mem_wdata,
    input  wire [DATA_W-1:0]  mem_rdata
//============================================//
);

//------------------------------- FSM logic ---------------------------------//
    localparam [2:0] S_IDLE = 3'h0, 
                     S_M0   = 3'h1, // ^(w0, r0)
                     S_M1   = 3'h2, // ^(r0, w1, r1)
                     S_M2   = 3'h3, // ^(r1, w0, r0)
                     S_DONE = 3'h4;

    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    wire [2:0] next_state = 
        (state == S_IDLE && start)                ? S_M0 :
        (state == S_M0 && step_done && addr_done) ? S_M1 :
        (state == S_M1 && step_done && addr_done) ? S_M2 :
        (state == S_M2 && step_done && addr_done) ? S_DONE : state;
//------------------------------------------------------------------------//

//---------------------------- CALCULATE STEP & ADDR --------------------------//   
    reg [1:0] step;
    reg [ADDR_W-1:0] addr;

    wire [1:0] max_step = (state == S_M0) ? 2'd1 :
                          (state == S_M1 || state == S_M2) ? 2'd2 : 
                          2'd0;

    wire step_done = (step == max_step);
    
    wire addr_done = (addr == (DEPTH - 1));

    wire [ADDR_W-1:0] next_addr = 
        (state == S_IDLE) || 
         (addr_done && step_done)      ? {ADDR_W{1'b0}} :
        (state == S_M0 || 
         state == S_M1 || 
         state == S_M2 ) && step_done  ? addr + 1'b1    : addr;    

    always @(posedge clk) begin
        if (rst) begin
            step  <= 2'd0;
            addr  <= {ADDR_W{1'b0}};
        end else begin
            addr  <= next_addr;
            step  <= (state == S_IDLE || step_done) ? 2'd0 :
                     step + 1'b1;
        end
    end
//--------------------------------------------------------------//

//---------------------------- OUTPUT INTO MEMORY -------------------//    
    assign mem_ce   =  (state == S_M0 | 
                        state == S_M1 | 
                        state == S_M2);

    assign mem_we   =  (state == S_M1 | state == S_M2) & step == 2'd1 |
                                       (state == S_M0) & step == 2'd0 ;
    assign mem_addr = addr;

    assign mem_wdata = {DATA_W{state == S_M1}}; 
//-----------------------------------------------------------------//

    
//----------------------------- CHECK DATA --------------------------//
    reg check_en;
    reg [ADDR_W-1:0] check_addr;
    reg [DATA_W-1:0] expected_data;
    wire exp_bit = (state == S_M1 & step == 2'd2 || state == S_M2 & step == 2'd0);

    always @(posedge clk) begin
        if (rst) begin
            check_en      <= 1'b0;
            check_addr    <= {ADDR_W{1'b0}};
            expected_data <= {DATA_W{1'b0}};
        end else begin
            check_en      <= mem_ce & !mem_we; // Активация проверки данных, если в прошлом такте было чтение
            check_addr    <= mem_ce & !mem_we  ? addr : check_addr;
            expected_data <= {DATA_W{exp_bit}};
        end
    end

    wire [DATA_W-1:0] check_mask   = mem_rdata ^ expected_data;
    wire              check_failed = (check_en && |check_mask);
//-----------------------------------------------------------------------//


//------------------------ HANDLE ERROR ----------------------------------//
    reg fail_reg;
    reg [ADDR_W-1:0] fail_addr_reg;
    reg [DATA_W-1:0] fail_addr_mask_reg;

    always @(posedge clk) begin
        if (rst) begin
            fail_reg           <= 1'b0;
            fail_addr_reg      <= {ADDR_W{1'b0}};
            fail_addr_mask_reg <= {ADDR_W{1'b0}};
        end else begin
            fail_reg           <= check_failed;
            fail_addr_reg      <= check_failed   ? check_addr : fail_addr_reg;
            fail_addr_mask_reg <= check_failed   ? check_mask : fail_addr_mask_reg;
        end
    end

    assign fail           = fail_reg;
    assign fail_addr      = fail_addr_reg;
    assign fail_addr_mask = fail_addr_mask_reg;
//-----------------------------------------------------------------------//

    assign done = (state == S_DONE);

endmodule