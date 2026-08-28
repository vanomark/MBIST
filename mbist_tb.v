`timescale 1ns / 1ps

module memory #(
    parameter DEPTH = 1000,
    parameter WIDTH = 32,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  wire              clock,
    input  wire              ce,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,         
    input  wire [WIDTH-1:0]  data_in,
    output wire [WIDTH-1:0]  data_out
);

    wire [WIDTH-1:0] word_out [0:DEPTH-1];
    reg  [WIDTH-1:0] out_reg;

    genvar i;
    generate
        for (i = 0; i < DEPTH; i = i + 1) begin : word
            reg [WIDTH-1:0] cell_word; 
            wire we_i = ce & we & (addr == i);

            always @(posedge clock) begin
                cell_word <= (we_i) ? data_in : cell_word;
            end

            assign word_out[i] = cell_word;
        end
    endgenerate

    always @(posedge clock) begin
        out_reg <= (ce && !we) ? word_out[addr] : out_reg;
    end

    assign data_out = out_reg;

endmodule


module tb_mbist;
    parameter DEPTH = 1000;
    parameter DATA_W = 32;
    parameter ADDR_W = $clog2(DEPTH);

    reg  clk = 0;
    reg  rst;
    reg  start;
    
    wire done;
    wire fail;
    wire [ADDR_W-1:0] fail_addr;
    wire [DATA_W-1:0] fail_addr_mask;
    
    wire mem_ce;
    wire mem_we;
    wire [ADDR_W-1:0] mem_addr;
    wire [DATA_W-1:0] mem_wdata;
    wire [DATA_W-1:0] mem_rdata;

    mbist dut (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .done           (done),
        .fail           (fail),
        .fail_addr      (fail_addr),
        .fail_addr_mask (fail_addr_mask),
        .mem_ce         (mem_ce),
        .mem_we         (mem_we),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_rdata      (mem_rdata)
    );

    memory #(
        .DEPTH (DEPTH),
        .WIDTH (DATA_W),
        .ADDR_W(ADDR_W)
    ) mock_mem (
        .clock   (clk),
        .ce      (mem_ce),
        .we      (mem_we),
        .addr    (mem_addr),
        .data_in (mem_wdata),
        .data_out(mem_rdata) 
    );

    always #5 clk = ~clk; 
    
    task apply_reset;
        begin
            rst = 1;
            start = 0;
            #25; 
            @(negedge clk);
            rst = 0;
        end
    endtask

    task run_bist;
        begin
            @(posedge clk) start = 1;
            @(posedge clk) start = 0;
            
            wait(done === 1'b1 || fail === 1'b1); 
        end
    endtask
    // ==========================================
    initial begin 
        $dumpvars();      
        $monitor("fail addr = ", fail_addr);

        $display("\n==================================================");
        $display(" HARDCORE STRUCTURAL MBIST VERIFICATION");
        $display("==================================================\n");

        // -----------------------------------------------------------
        // TEST 1: No defects
        // -----------------------------------------------------------
        $display("--- TEST 1: No defects ---");
        apply_reset();
        run_bist();
        
        if (fail === 1'b0 && done === 1'b1) 
            $display("[PASS] No false positives detected. TIME: %0t ps", $time);
        else 
            $display("[FAIL] BIST asserted FAIL on a healthy memory! TIME: %0t ps", $time);

        // -----------------------------------------------------------
        // TEST 2: Structural Stuck-At-1 (SAF-1) Injection
        // -----------------------------------------------------------
        $display("\n--- TEST 2: Structural Stuck-At-1 (SAF-1) Injection ---");
        apply_reset();
        
        // Physically forcing a specific bit in a specific word to 1
        force mock_mem.word[128].cell_word[5] = 1'b1;
        $display("[%0t ns] Fault injected: Word 128, Bit 5 is hardware locked to 1.", $time);
        
        run_bist();
        
        if (fail === 1'b1) 
            $display("[PASS] BIST caught the SAF-1 defect in the specific bit! TIME: %0t ps", $time);
        else 
            $display("[FAIL] BIST missed the single-bit structural SAF-1! TIME: %0t ps", $time);
            
        release mock_mem.word[128].cell_word[5]; // Fix the bit
        #10;

        // -----------------------------------------------------------
        // TEST 3: Random Data Corruption (Read Disturb Simulation)
        // -----------------------------------------------------------
        $display("\n--- TEST 3: Random Data Corruption ---");
        apply_reset();
        
        @(posedge clk) start = 1;
        @(posedge clk) start = 0;
        
        #15000; // Wait for BIST to initialize the memory array
        
        // Force an inversion on a specific bit to simulate charge flip
        force mock_mem.word[512].cell_word[12] = ~mock_mem.word[512].cell_word[12];
        #10; 
        release mock_mem.word[512].cell_word[12];
        $display("[%0t ns] Fault injected: Word 512, Bit 12 flipped.", $time);
        
        wait(done === 1'b1 || fail === 1'b1);
        
        if (fail === 1'b1) 
            $display("[PASS] BIST caught the data corruption! TIME: %0t ns", $time);
        else 
            $display("[FAIL] BIST missed the corrupted cell! TIME: %0t ns", $time);
        #10;

        $display("\n==================================================");
        $display(" VERIFICATION COMPLETED");
        $display("==================================================\n");

        #100 $finish; 
    end

endmodule