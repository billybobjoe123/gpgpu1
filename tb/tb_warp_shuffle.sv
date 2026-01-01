//=============================================================================
// GPGPU-1 Warp Shuffle Unit Testbench
//=============================================================================
// File:        tb_warp_shuffle.sv
// Description: Comprehensive testbench for the warp shuffle unit.
//              Tests all shuffle modes: IDX, UP, DOWN, BFLY, CLAMP, WRAP
// Version:     1.0
// Date:        January 1, 2026
//=============================================================================

`include "gpgpu_defines.svh"

module tb_warp_shuffle;
    import gpgpu_pkg::*;
    
    //=========================================================================
    // Parameters
    //=========================================================================
    
    localparam int NUM_LANES = WARP_SIZE;  // 8 lanes
    localparam int CLK_PERIOD = 10;
    
    //=========================================================================
    // Signals
    //=========================================================================
    
    logic clk;
    logic rst_n;
    
    // Shuffle control
    logic                    valid;
    logic [2:0]              shfl_func;
    logic [2:0]              shfl_width;
    logic [NUM_LANES-1:0]    active_mask;
    
    // Data
    logic [NUM_LANES-1:0][DATA_WIDTH-1:0] src_data;
    logic [NUM_LANES-1:0][DATA_WIDTH-1:0] lane_sel;
    logic [NUM_LANES-1:0][DATA_WIDTH-1:0] result;
    logic [NUM_LANES-1:0]    result_valid_mask;
    
    logic ready;
    logic done;
    
    // Test counters
    int tests_passed = 0;
    int tests_failed = 0;
    int total_tests = 0;
    
    //=========================================================================
    // DUT Instance
    //=========================================================================
    
    warp_shuffle #(
        .NUM_LANES(NUM_LANES)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .valid           (valid),
        .shfl_func       (shfl_func),
        .shfl_width      (shfl_width),
        .active_mask     (active_mask),
        
        .src_data        (src_data),
        .lane_sel        (lane_sel),
        
        .result          (result),
        .result_valid_mask(result_valid_mask),
        
        .ready           (ready),
        .done            (done)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    // Initialize source data with lane IDs * 10 for easy tracking
    task init_src_data();
        for (int i = 0; i < NUM_LANES; i++) begin
            src_data[i] = 64'd10 * i;  // Lane 0=0, 1=10, 2=20, ..., 7=70
        end
    endtask
    
    // Initialize source data with specific values
    task init_src_data_custom(input logic [NUM_LANES-1:0][DATA_WIDTH-1:0] data);
        src_data = data;
    endtask
    
    // Check single lane result
    task check_lane(
        input int lane,
        input logic [DATA_WIDTH-1:0] expected,
        input logic expected_valid,
        input string test_name
    );
        total_tests++;
        if (result[lane] !== expected && expected_valid) begin
            $display("[FAIL] %s Lane %0d: Expected 0x%h, Got 0x%h", 
                     test_name, lane, expected, result[lane]);
            tests_failed++;
        end else if (result_valid_mask[lane] !== expected_valid) begin
            $display("[FAIL] %s Lane %0d: Expected valid=%0b, Got valid=%0b", 
                     test_name, lane, expected_valid, result_valid_mask[lane]);
            tests_failed++;
        end else begin
            $display("[PASS] %s Lane %0d: Got 0x%h (valid=%0b)", 
                     test_name, lane, result[lane], result_valid_mask[lane]);
            tests_passed++;
        end
    endtask
    
    // Run shuffle operation
    task run_shuffle(
        input logic [2:0] func,
        input logic [2:0] width,
        input logic [NUM_LANES-1:0] mask
    );
        shfl_func = func;
        shfl_width = width;
        active_mask = mask;
        valid = 1'b1;
        #(CLK_PERIOD);
        valid = 1'b0;
    endtask
    
    //=========================================================================
    // Test Cases
    //=========================================================================
    
    initial begin
        $display("==============================================");
        $display("Warp Shuffle Unit Testbench");
        $display("==============================================");
        $display("  Warp Size: %0d", NUM_LANES);
        $display("==============================================\n");
        
        // Initialize
        rst_n = 0;
        valid = 0;
        shfl_func = 0;
        shfl_width = 0;
        active_mask = '0;
        src_data = '0;
        lane_sel = '0;
        
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);
        
        //=====================================================================
        // Test 1: SHFL_IDX - Direct Index Shuffle
        //=====================================================================
        $display("\n--- Test: SHFL_IDX (Direct Index) ---");
        init_src_data();  // 0, 10, 20, 30, 40, 50, 60, 70
        
        // All lanes select lane 3
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd3;
        run_shuffle(SHFL_IDX, 3'b000, 8'hFF);  // Full warp width
        
        for (int i = 0; i < NUM_LANES; i++) begin
            check_lane(i, 64'd30, 1'b1, "SHFL_IDX broadcast lane 3");
        end
        
        // Each lane selects its own ID (identity)
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = i;
        run_shuffle(SHFL_IDX, 3'b000, 8'hFF);
        
        for (int i = 0; i < NUM_LANES; i++) begin
            check_lane(i, 64'd10 * i, 1'b1, "SHFL_IDX identity");
        end
        
        // Reverse order: lane i selects lane (7-i)
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 7 - i;
        run_shuffle(SHFL_IDX, 3'b000, 8'hFF);
        
        check_lane(0, 64'd70, 1'b1, "SHFL_IDX reverse");
        check_lane(7, 64'd0, 1'b1, "SHFL_IDX reverse");
        
        //=====================================================================
        // Test 2: SHFL_UP - Shift Up (get from lower lane)
        //=====================================================================
        $display("\n--- Test: SHFL_UP (Shift Up) ---");
        init_src_data();
        
        // Shift up by 1: lane[i] = src[i-1], lane 0 gets nothing valid
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd1;
        run_shuffle(SHFL_UP, 3'b000, 8'hFF);
        
        check_lane(0, 64'd0, 1'b0, "SHFL_UP delta=1");  // Invalid - no lane -1
        check_lane(1, 64'd0, 1'b1, "SHFL_UP delta=1");  // Gets lane 0
        check_lane(2, 64'd10, 1'b1, "SHFL_UP delta=1"); // Gets lane 1
        check_lane(7, 64'd60, 1'b1, "SHFL_UP delta=1"); // Gets lane 6
        
        // Shift up by 2
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd2;
        run_shuffle(SHFL_UP, 3'b000, 8'hFF);
        
        check_lane(0, 64'd0, 1'b0, "SHFL_UP delta=2");  // Invalid
        check_lane(1, 64'd10, 1'b0, "SHFL_UP delta=2"); // Invalid (would be lane -1)
        check_lane(2, 64'd0, 1'b1, "SHFL_UP delta=2");  // Gets lane 0
        check_lane(3, 64'd10, 1'b1, "SHFL_UP delta=2"); // Gets lane 1
        
        //=====================================================================
        // Test 3: SHFL_DOWN - Shift Down (get from higher lane)
        //=====================================================================
        $display("\n--- Test: SHFL_DOWN (Shift Down) ---");
        init_src_data();
        
        // Shift down by 1: lane[i] = src[i+1], lane 7 gets nothing valid
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd1;
        run_shuffle(SHFL_DOWN, 3'b000, 8'hFF);
        
        check_lane(0, 64'd10, 1'b1, "SHFL_DOWN delta=1"); // Gets lane 1
        check_lane(6, 64'd70, 1'b1, "SHFL_DOWN delta=1"); // Gets lane 7
        check_lane(7, 64'd70, 1'b0, "SHFL_DOWN delta=1"); // Invalid - no lane 8
        
        // Shift down by 3
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd3;
        run_shuffle(SHFL_DOWN, 3'b000, 8'hFF);
        
        check_lane(0, 64'd30, 1'b1, "SHFL_DOWN delta=3"); // Gets lane 3
        check_lane(4, 64'd70, 1'b1, "SHFL_DOWN delta=3"); // Gets lane 7
        check_lane(5, 64'd50, 1'b0, "SHFL_DOWN delta=3"); // Invalid
        
        //=====================================================================
        // Test 4: SHFL_BFLY - Butterfly (XOR) Shuffle
        //=====================================================================
        $display("\n--- Test: SHFL_BFLY (Butterfly XOR) ---");
        init_src_data();
        
        // XOR with 1: swap adjacent pairs (0<->1, 2<->3, 4<->5, 6<->7)
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd1;
        run_shuffle(SHFL_BFLY, 3'b000, 8'hFF);
        
        check_lane(0, 64'd10, 1'b1, "SHFL_BFLY mask=1"); // 0^1=1
        check_lane(1, 64'd0, 1'b1, "SHFL_BFLY mask=1");  // 1^1=0
        check_lane(2, 64'd30, 1'b1, "SHFL_BFLY mask=1"); // 2^1=3
        check_lane(3, 64'd20, 1'b1, "SHFL_BFLY mask=1"); // 3^1=2
        
        // XOR with 2: swap pairs at distance 2 (0<->2, 1<->3, 4<->6, 5<->7)
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd2;
        run_shuffle(SHFL_BFLY, 3'b000, 8'hFF);
        
        check_lane(0, 64'd20, 1'b1, "SHFL_BFLY mask=2"); // 0^2=2
        check_lane(1, 64'd30, 1'b1, "SHFL_BFLY mask=2"); // 1^2=3
        check_lane(2, 64'd0, 1'b1, "SHFL_BFLY mask=2");  // 2^2=0
        
        // XOR with 4: swap halves (0<->4, 1<->5, 2<->6, 3<->7)
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd4;
        run_shuffle(SHFL_BFLY, 3'b000, 8'hFF);
        
        check_lane(0, 64'd40, 1'b1, "SHFL_BFLY mask=4"); // 0^4=4
        check_lane(4, 64'd0, 1'b1, "SHFL_BFLY mask=4");  // 4^4=0
        check_lane(7, 64'd30, 1'b1, "SHFL_BFLY mask=4"); // 7^4=3
        
        //=====================================================================
        // Test 5: SHFL_CLAMP - Clamped Up Shuffle
        //=====================================================================
        $display("\n--- Test: SHFL_CLAMP (Clamped Up) ---");
        init_src_data();
        
        // Clamp up by 2: lane[i] = src[max(i-2, 0)]
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd2;
        run_shuffle(SHFL_CLAMP, 3'b000, 8'hFF);
        
        check_lane(0, 64'd0, 1'b1, "SHFL_CLAMP delta=2");  // max(0-2,0)=0
        check_lane(1, 64'd0, 1'b1, "SHFL_CLAMP delta=2");  // max(1-2,0)=0
        check_lane(2, 64'd0, 1'b1, "SHFL_CLAMP delta=2");  // max(2-2,0)=0
        check_lane(3, 64'd10, 1'b1, "SHFL_CLAMP delta=2"); // max(3-2,0)=1
        check_lane(7, 64'd50, 1'b1, "SHFL_CLAMP delta=2"); // max(7-2,0)=5
        
        //=====================================================================
        // Test 6: SHFL_WRAP - Wrapped Shuffle
        //=====================================================================
        $display("\n--- Test: SHFL_WRAP (Wrapped) ---");
        init_src_data();
        
        // Wrap by 1: lane[i] = src[(i+1) % 8]
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd1;
        run_shuffle(SHFL_WRAP, 3'b000, 8'hFF);
        
        check_lane(0, 64'd10, 1'b1, "SHFL_WRAP delta=1"); // (0+1)%8=1
        check_lane(6, 64'd70, 1'b1, "SHFL_WRAP delta=1"); // (6+1)%8=7
        check_lane(7, 64'd0, 1'b1, "SHFL_WRAP delta=1");  // (7+1)%8=0 (wrapped!)
        
        // Wrap by 3
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd3;
        run_shuffle(SHFL_WRAP, 3'b000, 8'hFF);
        
        check_lane(0, 64'd30, 1'b1, "SHFL_WRAP delta=3"); // (0+3)%8=3
        check_lane(5, 64'd0, 1'b1, "SHFL_WRAP delta=3");  // (5+3)%8=0
        check_lane(7, 64'd20, 1'b1, "SHFL_WRAP delta=3"); // (7+3)%8=2
        
        //=====================================================================
        // Test 7: Segmented Shuffle (width=4)
        //=====================================================================
        $display("\n--- Test: Segmented Shuffle (width=4) ---");
        init_src_data();
        
        // Broadcast lane 0 within each 4-lane segment
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd0;
        run_shuffle(SHFL_IDX, 3'b010, 8'hFF);  // width=4
        
        // Segment 0 (lanes 0-3): all get lane 0
        check_lane(0, 64'd0, 1'b1, "SHFL_IDX seg width=4");
        check_lane(1, 64'd0, 1'b1, "SHFL_IDX seg width=4");
        check_lane(2, 64'd0, 1'b1, "SHFL_IDX seg width=4");
        check_lane(3, 64'd0, 1'b1, "SHFL_IDX seg width=4");
        
        // Segment 1 (lanes 4-7): all get lane 4 (base of segment)
        check_lane(4, 64'd40, 1'b1, "SHFL_IDX seg width=4");
        check_lane(5, 64'd40, 1'b1, "SHFL_IDX seg width=4");
        check_lane(6, 64'd40, 1'b1, "SHFL_IDX seg width=4");
        check_lane(7, 64'd40, 1'b1, "SHFL_IDX seg width=4");
        
        //=====================================================================
        // Test 8: Partial Active Mask
        //=====================================================================
        $display("\n--- Test: Partial Active Mask ---");
        init_src_data();
        
        // Only even lanes active
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd1;
        run_shuffle(SHFL_DOWN, 3'b000, 8'b01010101);
        
        check_lane(0, 64'd10, 1'b0, "SHFL_DOWN partial"); // Valid but src lane 1 inactive
        check_lane(2, 64'd30, 1'b0, "SHFL_DOWN partial"); // Valid but src lane 3 inactive
        check_lane(1, 64'd0, 1'b0, "SHFL_DOWN partial");  // Lane 1 inactive
        
        //=====================================================================
        // Test 9: Reduction Pattern (butterfly reduce)
        //=====================================================================
        $display("\n--- Test: Butterfly Reduction Pattern ---");
        // Test classic reduction: XOR 4, XOR 2, XOR 1
        for (int i = 0; i < NUM_LANES; i++) src_data[i] = 64'd1;  // All 1s
        
        // This tests the pattern used for warp-level reductions
        for (int i = 0; i < NUM_LANES; i++) lane_sel[i] = 64'd4;
        run_shuffle(SHFL_BFLY, 3'b000, 8'hFF);
        
        // All lanes should still have 1 (data from partner lane)
        check_lane(0, 64'd1, 1'b1, "SHFL_BFLY reduce step");
        check_lane(4, 64'd1, 1'b1, "SHFL_BFLY reduce step");
        
        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n==============================================");
        $display("Test Summary");
        $display("==============================================");
        $display("Total Tests: %0d", total_tests);
        $display("Passed:      %0d", tests_passed);
        $display("Failed:      %0d", tests_failed);
        $display("==============================================\n");
        
        if (tests_failed == 0) begin
            $display("*** ALL WARP SHUFFLE TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end
        
        $finish;
    end

endmodule
