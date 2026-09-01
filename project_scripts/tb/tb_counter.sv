`timescale 1ns / 1ps

//==============================================================================
/*
  Testbench Name : tb_counter

  Description :
    Self-checking functional testbench for the parameterized counter module.

  Test goals:
    - Verify asynchronous active-low reset behavior.
    - Verify that the counter holds its value while en = 0.
    - Verify counting while en = 1.
    - Verify pause and resume operation.
    - Verify synchronous clear behavior.
    - Verify that clr has priority over en.
    - Verify wrap-around from the maximum value back to zero.
    - Verify asynchronous reset during active operation.

  Independent golden-model methodology:
    - The golden model does NOT reproduce the DUT always_ff block or its
      internal if/else implementation.
    - The testbench keeps an independent count of accepted increment events.
    - The expected counter value is derived mathematically as:

          expected = increment_events mod 2^WIDTH

    - Reset and clear restart the externally observed counting sequence from 0.
    - Therefore, expected values are derived from the stimulus history and the
      counter specification, not by duplicating the RTL implementation.

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes are made only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges when
      asynchronous reset behavior is tested.
*/
//==============================================================================

module tb_counter;

    //==========================================================================
    // Testbench Parameters
    //==========================================================================

    localparam int WIDTH = 4;
    localparam int COUNTER_VALUES = (1 << WIDTH);
    localparam time CLK_PERIOD = 10ns;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic                 clk;
    logic                 resetb;
    logic                 en;
    logic                 clr;
    logic [WIDTH-1:0]     count;


    //==========================================================================
    // Independent Golden Model / Test Status
    //==========================================================================

    int unsigned increment_events;
    int unsigned error_count;
    int unsigned check_count;

    logic reset_covered;
    logic hold_covered;
    logic count_covered;
    logic pause_resume_covered;
    logic clear_covered;
    logic clear_priority_covered;
    logic wrap_covered;
    logic mid_operation_reset_covered;


    //==========================================================================
    // DUT Instance
    //==========================================================================

    counter #(
        .WIDTH(WIDTH)
    ) dut (
        .clk    (clk),
        .resetb (resetb),
        .en     (en),
        .clr    (clr),
        .count  (count)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;


    //==========================================================================
    // Utility Tasks
    //==========================================================================

    //--------------------------------------------------------------------------
    // Synchronization task
    //
    // Normal stimulus is changed immediately after sync() returns.
    // resetb assertion is intentionally excluded when asynchronous behavior
    // is being tested.
    //--------------------------------------------------------------------------

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //--------------------------------------------------------------------------
    // Print a clear test banner in the transcript.
    //--------------------------------------------------------------------------

    task automatic print_banner(input string test_name);
        begin
            $display("");
            $display("================================================================");
            $display("START TEST: %s", test_name);
            $display("TIME      : %0t", $time);
            $display("================================================================");
        end
    endtask


    //--------------------------------------------------------------------------
    // Return the expected WIDTH-bit value from the independent event count.
    //--------------------------------------------------------------------------

    function automatic logic [WIDTH-1:0] expected_value;
        expected_value = increment_events % COUNTER_VALUES;
    endfunction


    //--------------------------------------------------------------------------
    // Check the DUT counter against the independent golden model.
    //--------------------------------------------------------------------------

    task automatic check_count_value(input string check_name);
        logic [WIDTH-1:0] expected;
        begin
            expected = expected_value();
            check_count = check_count + 1;

            if (count !== expected) begin
                error_count = error_count + 1;
                $error("[%s] FAILED: count=%0d, expected=%0d, increment_events=%0d",
                       check_name, count, expected, increment_events);
            end
            else begin
                $display("[%s] PASS: count=%0d, expected=%0d",
                         check_name, count, expected);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Apply one enabled counting cycle.
    //
    // The golden model is updated from the externally requested operation,
    // rather than from any DUT internal signal or copied RTL equation.
    //--------------------------------------------------------------------------

    task automatic count_one_cycle(input string check_name);
        begin
            sync();
            en  = 1'b1;
            clr = 1'b0;

            sync();
            increment_events = increment_events + 1;
            check_count_value(check_name);
        end
    endtask


    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    initial begin

        error_count      = 0;
        check_count      = 0;
        increment_events = 0;

        reset_covered               = 1'b0;
        hold_covered                = 1'b0;
        count_covered               = 1'b0;
        pause_resume_covered        = 1'b0;
        clear_covered               = 1'b0;
        clear_priority_covered      = 1'b0;
        wrap_covered                = 1'b0;
        mid_operation_reset_covered = 1'b0;

        en     = 1'b0;
        clr    = 1'b0;
        resetb = 1'b1;


        //======================================================================
        // TEST 1 - Asynchronous reset
        //
        // resetb is asserted between clock edges. count must clear immediately,
        // without waiting for the next rising edge.
        //======================================================================

        print_banner("TEST 1 - Asynchronous reset");

        sync();
        en = 1'b1;

        sync();
        increment_events = increment_events + 1;
        check_count_value("TEST 1A - Counter active before reset");

        #(CLK_PERIOD/4);
        resetb = 1'b0;
        increment_events = 0;
        #1ps;

        check_count_value("TEST 1B - Immediate asynchronous reset");
        reset_covered = 1'b1;

        sync();
        resetb = 1'b1;
        en     = 1'b0;
        clr    = 1'b0;

        sync();
        check_count_value("TEST 1C - Reset release");


        //======================================================================
        // TEST 2 - Hold while disabled
        //
        // The counter must remain unchanged over several clock cycles when
        // en = 0 and clr = 0.
        //======================================================================

        print_banner("TEST 2 - Hold while disabled");

        repeat (3) begin
            sync();
            check_count_value("TEST 2 - Disabled hold");
        end

        hold_covered = 1'b1;


        //======================================================================
        // TEST 3 - Normal counting
        //
        // Apply five accepted increment events and verify the observed count
        // after every event.
        //======================================================================

        print_banner("TEST 3 - Normal counting");

        repeat (5)
            count_one_cycle("TEST 3 - Increment");

        count_covered = 1'b1;


        //======================================================================
        // TEST 4 - Pause and resume
        //
        // Disable the counter for several cycles, verify that it holds, then
        // resume counting and verify that the sequence continues correctly.
        //======================================================================

        print_banner("TEST 4 - Pause and resume");

        sync();
        en = 1'b0;

        repeat (3) begin
            sync();
            check_count_value("TEST 4A - Paused");
        end

        count_one_cycle("TEST 4B - Resume counting");
        pause_resume_covered = 1'b1;


        //======================================================================
        // TEST 5 - Synchronous clear
        //
        // clr is asserted after sync(). The current count must remain unchanged
        // until the following rising edge, where it is synchronously cleared.
        //======================================================================

        print_banner("TEST 5 - Synchronous clear");

        sync();
        en  = 1'b0;
        clr = 1'b1;

        #1ps;
        check_count_value("TEST 5A - Clear has not yet been sampled");

        sync();
        increment_events = 0;
        check_count_value("TEST 5B - Clear sampled on rising edge");

        clr = 1'b0;
        clear_covered = 1'b1;


        //======================================================================
        // TEST 6 - Clear priority over enable
        //
        // Assert en and clr together. According to the module specification,
        // synchronous clear must win and no increment event is accepted.
        //======================================================================

        print_banner("TEST 6 - Clear priority over enable");

        count_one_cycle("TEST 6A - Establish non-zero count");

        sync();
        en  = 1'b1;
        clr = 1'b1;

        sync();
        increment_events = 0;
        check_count_value("TEST 6B - Clear wins over enable");

        clr = 1'b0;
        en  = 1'b0;
        clear_priority_covered = 1'b1;


        //======================================================================
        // TEST 7 - Wrap-around
        //
        // Generate exactly 2^WIDTH accepted increment events starting from 0.
        // The final expected value is therefore 0 modulo 2^WIDTH.
        //======================================================================

        print_banner("TEST 7 - Counter wrap-around");

        repeat (COUNTER_VALUES)
            count_one_cycle("TEST 7 - Wrap sequence");

        if (count === {WIDTH{1'b0}}) begin
            $display("[TEST 7] PASS: counter wrapped from maximum value to zero");
            wrap_covered = 1'b1;
        end
        else begin
            error_count = error_count + 1;
            $error("[TEST 7] FAILED: expected wrap to zero, count=%0d", count);
        end


        //======================================================================
        // TEST 8 - Asynchronous reset during operation
        //
        // Start counting again, then assert resetb between clock edges while
        // en remains high. count must clear immediately.
        //======================================================================

        print_banner("TEST 8 - Asynchronous reset during operation");

        count_one_cycle("TEST 8A - First active count");
        count_one_cycle("TEST 8B - Second active count");

        #(CLK_PERIOD/2);
        resetb = 1'b0;
        increment_events = 0;
        #1ps;

        check_count_value("TEST 8C - Mid-operation asynchronous reset");
        mid_operation_reset_covered = 1'b1;

        sync();
        resetb = 1'b1;
        en     = 1'b0;
        clr    = 1'b0;

        sync();
        check_count_value("TEST 8D - Final reset release");


        //======================================================================
        // Coverage Summary
        //======================================================================

        $display("");
        $display("================================================================");
        $display("COVERAGE SUMMARY");
        $display("================================================================");
        $display("Asynchronous reset             : %0d", reset_covered);
        $display("Disabled hold                  : %0d", hold_covered);
        $display("Normal counting                : %0d", count_covered);
        $display("Pause / resume                 : %0d", pause_resume_covered);
        $display("Synchronous clear              : %0d", clear_covered);
        $display("Clear priority over enable     : %0d", clear_priority_covered);
        $display("Counter wrap-around            : %0d", wrap_covered);
        $display("Reset during active operation  : %0d", mid_operation_reset_covered);

        check_count = check_count + 1;
        if (!(reset_covered               &&
              hold_covered                &&
              count_covered               &&
              pause_resume_covered        &&
              clear_covered               &&
              clear_priority_covered      &&
              wrap_covered                &&
              mid_operation_reset_covered)) begin
            error_count = error_count + 1;
            $error("Coverage FAILED: not all directed scenarios were covered");
        end


        //======================================================================
        // Final Test Summary
        //======================================================================

        $display("");
        $display("================================================================");
        $display("FINAL TEST SUMMARY");
        $display("================================================================");
        $display("Checks performed : %0d", check_count);
        $display("Errors found      : %0d", error_count);

        if (error_count == 0)
            $display("RESULT            : PASS");
        else
            $display("RESULT            : FAIL");

        $display("================================================================");
        $display("");

        $finish;
    end

endmodule
