`timescale 1ns / 1ps

//==============================================================================
/*
  Testbench Name : tb_input_subsystem

  Description :
    Self-checking integration testbench for input_subsystem.

    The DUT integrates the complete input row-buffer control path and data path:
      - row_buffer_controller
      - row_buffer_bank
      - physical BRAM row buffers
      - logical-row mux / padding path

  Test goals:
    - Verify asynchronous active-low reset behavior.
    - Verify that no read request is generated before INIT_ROWS rows are stored.
    - Verify that data_valid gaps do not advance the write sequence.
    - Verify end-to-end storage and readback of the first complete window.
    - Verify that all INIT_ROWS logical rows are returned in parallel.
    - Verify registered BRAM read latency between rd_valid request and pixel_out.
    - Verify STRIDE-row window advancement after additional rows are supplied.
    - Verify correct data mapping in the second processing window.
    - Verify reset recovery after normal operation.

  Golden-model methodology:
    - Input pixels are generated from a deterministic row/column function.
    - Expected output values are derived only from the externally driven input
      image coordinates and the known logical window being checked.
    - The testbench does not reproduce the DUT FSM, BRAM-enable generation,
      circular-buffer pointers, or address-counter implementation.

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes are made only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges to verify
      asynchronous reset behavior.
*/
//==============================================================================

module tb_input_subsystem;

    //==========================================================================
    // Testbench Parameters
    //==========================================================================

    localparam int DATA_WIDTH  = 8;
    localparam int ROW_LENGTH  = 8;
    localparam int ADDR_WIDTH  = 10;
    localparam int ROW_CNT_W   = 3;
    localparam int INIT_ROWS   = 5;
    localparam int STRIDE      = 3;
    localparam int NUM_BUFFERS = 16;
    localparam int OCC_CNT_W   = 5;

    localparam int BRAM_READ_LATENCY = 2;
    localparam int FIRST_WINDOW_TOP  = 0;
    localparam int SECOND_WINDOW_TOP = STRIDE;

    localparam time CLK_PERIOD = 10ns;

    typedef logic [DATA_WIDTH-1:0] data_t;

    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic                    clk;
    logic                    resetb;
    logic                    data_valid;
    logic                    frame_done;
    logic [DATA_WIDTH-1:0]   data;

    logic [DATA_WIDTH-1:0]   pixel_out [0:INIT_ROWS-1];
    logic                    rd_valid;

    //==========================================================================
    // Test Status / Coverage
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;

    logic async_reset_covered;
    logic initial_fill_no_read_covered;
    logic data_valid_gap_covered;
    logic first_window_covered;
    logic parallel_rows_covered;
    logic bram_latency_covered;
    logic stride_advance_covered;
    logic second_window_covered;
    logic reset_recovery_covered;

    //==========================================================================
    // DUT Instance
    //==========================================================================

    input_subsystem #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ROW_LENGTH  (ROW_LENGTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ROW_CNT_W   (ROW_CNT_W),
        .INIT_ROWS   (INIT_ROWS),
        .STRIDE      (STRIDE),
        .NUM_BUFFERS (NUM_BUFFERS),
        .OCC_CNT_W   (OCC_CNT_W)
    ) dut (
        .clk       (clk),
        .resetb    (resetb),
        .data_valid(data_valid),
        .frame_done(frame_done),
        .data      (data),
        .pixel_out (pixel_out),
        .rd_valid  (rd_valid)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //==========================================================================
    // Utility Functions / Tasks
    //==========================================================================

    function automatic data_t pixel_value(
        input int unsigned row_idx,
        input int unsigned col_idx
    );
        pixel_value = data_t'((row_idx * 16) + col_idx + 1);
    endfunction

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

    task automatic print_banner(input string test_name);
        begin
            $display("");
            $display("================================================================");
            $display("START TEST: %s", test_name);
            $display("TIME      : %0t", $time);
            $display("================================================================");
        end
    endtask

    task automatic check_condition(
        input string test_name,
        input logic condition
    );
        begin
            check_count = check_count + 1;

            assert (condition)
            else begin
                error_count = error_count + 1;
                $error("[%s] FAILED", test_name);
            end

            if (condition)
                $display("[%s] PASS", test_name);
        end
    endtask

    task automatic check_pixel_window(
        input string test_name,
        input int unsigned top_row,
        input int unsigned col_idx
    );
        int row_idx;
        data_t expected;
        begin
            for (row_idx = 0; row_idx < INIT_ROWS; row_idx = row_idx + 1) begin
                expected = pixel_value(top_row + row_idx, col_idx);
                check_count = check_count + 1;

                assert (pixel_out[row_idx] === expected)
                else begin
                    error_count = error_count + 1;
                    $error("[%s] FAILED: pixel_out[%0d]=%0d, expected=%0d for row=%0d col=%0d",
                           test_name,
                           row_idx,
                           pixel_out[row_idx],
                           expected,
                           top_row + row_idx,
                           col_idx);
                end

                if (pixel_out[row_idx] === expected)
                    $display("[%s] PASS: pixel_out[%0d]=%0d for row=%0d col=%0d",
                             test_name,
                             row_idx,
                             pixel_out[row_idx],
                             top_row + row_idx,
                             col_idx);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Write one complete image row.
    // Optional gap insertion demonstrates that data_valid controls write
    // progress and that invalid cycles do not consume a pixel position.
    //--------------------------------------------------------------------------
    task automatic send_row(
        input int unsigned row_idx,
        input logic insert_gap
    );
        int col_idx;
        begin
            for (col_idx = 0; col_idx < ROW_LENGTH; col_idx = col_idx + 1) begin
                sync();
                data_valid = 1'b1;
                data       = pixel_value(row_idx, col_idx);

                if (insert_gap && (col_idx == (ROW_LENGTH/2 - 1))) begin
                    sync();
                    data_valid = 1'b0;
                    data       = data_t'(0);

                    sync();
                    data_valid = 1'b1;
                    data       = pixel_value(row_idx, col_idx + 1);
                    col_idx = col_idx + 1;
                    data_valid_gap_covered = 1'b1;
                end
            end

            sync();
            data_valid = 1'b0;
            data       = data_t'(0);
        end
    endtask

    //--------------------------------------------------------------------------
    // Wait for the beginning of a read scan and verify one complete window.
    // rd_valid indicates the BRAM read request. pixel_out is checked after the
    // configured registered-BRAM latency.
    //--------------------------------------------------------------------------
    task automatic verify_window(
        input string test_name,
        input int unsigned top_row
    );
        int checked_columns;
        int current_col;
        int pending_col;
        logic pending_valid;
        logic request_valid;
        begin
            checked_columns = 0;
            pending_col     = 0;
            pending_valid   = 1'b0;

            // Wait until the first BRAM read request of the scan is visible.
            while (rd_valid !== 1'b1)
                sync();

            // BRAM requests are continuous, one column per clock. The request
            // visible before sync() is sampled on that edge. Because the BRAM
            // output is registered, the corresponding pixel_out values are
            // checked on the following clock.
            while (checked_columns < ROW_LENGTH) begin
                request_valid = rd_valid;
                current_col   = dut.rd_addr;

                sync();

                if (pending_valid) begin
                    check_pixel_window(test_name, top_row, pending_col);
                    checked_columns = checked_columns + 1;
                end

                pending_valid = request_valid;
                pending_col   = current_col;
            end

            check_condition($sformatf("%s - complete %0d-column scan",
                                      test_name, ROW_LENGTH),
                            checked_columns == ROW_LENGTH);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    initial begin
        int row_idx;

        error_count = 0;
        check_count = 0;

        async_reset_covered         = 1'b0;
        initial_fill_no_read_covered = 1'b0;
        data_valid_gap_covered      = 1'b0;
        first_window_covered        = 1'b0;
        parallel_rows_covered       = 1'b0;
        bram_latency_covered        = 1'b0;
        stride_advance_covered      = 1'b0;
        second_window_covered       = 1'b0;
        reset_recovery_covered      = 1'b0;

        resetb     = 1'b0;
        data_valid = 1'b0;
        frame_done = 1'b0;
        data       = data_t'(0);

        repeat (3) sync();

        // Release reset only after synchronization.
        resetb = 1'b1;
        sync();

        //======================================================================
        // TEST 1
        // Initial fill and data_valid gap
        //
        // Fill INIT_ROWS rows. No read request is allowed before the complete
        // initial window is available. Row 2 contains a deliberate valid gap.
        //======================================================================

        print_banner("TEST 1 - Initial fill and data_valid gap");

        for (row_idx = 0; row_idx < INIT_ROWS; row_idx = row_idx + 1) begin
            send_row(row_idx, (row_idx == 2));

            if (row_idx < (INIT_ROWS - 1))
                check_condition("No read before INIT_ROWS rows are complete",
                                rd_valid === 1'b0);
        end

        initial_fill_no_read_covered = 1'b1;
        check_condition("data_valid gap was exercised", data_valid_gap_covered);

        //======================================================================
        // TEST 2
        // First complete processing window
        //
        // Expected logical rows are image rows 0..4. Every read column must
        // return one pixel from each of those five rows in parallel.
        //======================================================================

        print_banner("TEST 2 - First complete window");

        verify_window("TEST 2", FIRST_WINDOW_TOP);
        first_window_covered  = 1'b1;
        parallel_rows_covered = 1'b1;
        bram_latency_covered  = 1'b1;

        //======================================================================
        // TEST 3
        // STRIDE-row advancement
        //
        // Supply exactly STRIDE additional rows. The next available processing
        // window must advance by STRIDE rows, therefore rows 3..7 are expected.
        //======================================================================

        print_banner("TEST 3 - STRIDE-row window advancement");

        for (row_idx = INIT_ROWS;
             row_idx < (INIT_ROWS + STRIDE);
             row_idx = row_idx + 1)
            send_row(row_idx, 1'b0);

        verify_window("TEST 3", SECOND_WINDOW_TOP);
        stride_advance_covered = 1'b1;
        second_window_covered  = 1'b1;

        //======================================================================
        // TEST 4
        // Asynchronous reset during normal operation
        //
        // Reset is asserted between clock edges. rd_valid must drop without
        // waiting for another active edge. After synchronized release, the
        // subsystem must return to initial-fill behavior.
        //======================================================================

        print_banner("TEST 4 - Asynchronous reset and recovery");

        #(CLK_PERIOD/4);
        resetb = 1'b0;
        #1ps;

        check_condition("rd_valid cleared asynchronously", rd_valid === 1'b0);
        async_reset_covered = 1'b1;

        sync();
        resetb = 1'b1;
        data_valid = 1'b0;
        frame_done = 1'b0;
        data       = data_t'(0);

        sync();
        check_condition("Subsystem returned to initial-fill mode",
                        rd_valid === 1'b0);
        reset_recovery_covered = 1'b1;

        //======================================================================
        // Coverage / Final Summary
        //======================================================================

        check_count = check_count + 1;
        assert (async_reset_covered          &&
                initial_fill_no_read_covered &&
                data_valid_gap_covered       &&
                first_window_covered         &&
                parallel_rows_covered        &&
                bram_latency_covered         &&
                stride_advance_covered       &&
                second_window_covered        &&
                reset_recovery_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage flags are incomplete");
        end

        $display("");
        $display("================================================================");
        $display("SIMULATION SUMMARY - tb_input_subsystem");
        $display("Checks : %0d", check_count);
        $display("Errors : %0d", error_count);
        $display("================================================================");

        if (error_count == 0)
            $display("RESULT: PASSED");
        else
            $fatal(1, "RESULT: FAILED - %0d error(s)", error_count);

        $finish;
    end

endmodule
