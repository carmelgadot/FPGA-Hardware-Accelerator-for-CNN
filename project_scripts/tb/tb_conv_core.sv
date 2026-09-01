//==============================================================================
/*
  Testbench Name : tb_conv_core

  Description :
    Self-checking testbench for conv_core.

    The DUT performs three parallel 3x3 convolutions over five input-row
    streams and then applies the project post-processing:

        y_out = saturate(2*y_conv + 128)

    The reference model is intentionally independent of the RTL structure.
    It does NOT reproduce the PE hierarchy, PE partial sums, or internal
    conv_core implementation. Instead, it calculates each 3x3 convolution
    directly from the mathematical definition using nine products.

    The testbench also models only the externally observable pipeline delay.
    A completed 3-pixel horizontal window is expected at data_out three clock
    cycles later.

  Test Method :
    - All normal stimulus changes are made immediately after sync() returns.
    - resetb assertion is tested asynchronously between clock edges.
    - resetb deassertion is performed only after sync().
    - The golden model uses integer arithmetic and direct 3x3 convolution.
    - The DUT is checked only through its external outputs.
    - Directed tests cover signed kernels, high unsigned pixel values,
      saturation at both limits, all nine kernel positions, and reset.
*/
//==============================================================================

module tb_conv_core;

    //==========================================================================
    // Parameters
    //==========================================================================

    localparam int  DATA_WIDTH = 8;
    localparam time CLK_PERIOD = 10ns;
    localparam int  PIPELINE_DELAY = 3;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;

    logic [DATA_WIDTH-1:0] input_pixel0;
    logic [DATA_WIDTH-1:0] input_pixel1;
    logic [DATA_WIDTH-1:0] input_pixel2;
    logic [DATA_WIDTH-1:0] input_pixel3;
    logic [DATA_WIDTH-1:0] input_pixel4;

    logic signed [DATA_WIDTH-1:0] kernel [0:8];

    logic [DATA_WIDTH-1:0] data_out0;
    logic [DATA_WIDTH-1:0] data_out1;
    logic [DATA_WIDTH-1:0] data_out2;


    //==========================================================================
    // Test Status
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;


    //==========================================================================
    // Independent Reference Model State
    //==========================================================================

    // Five input rows, each storing the last three captured pixels.
    // Index 0 = oldest pixel, index 2 = newest pixel.
    int unsigned row_history [0:4][0:2];

    // Integer copy of the programmed kernel. This keeps the golden arithmetic
    // independent of the DUT's packed-vector arithmetic and internal widths.
    int signed ref_kernel [0:8];

    // Expected output pipeline. The reference result is delayed only to match
    // the observable DUT latency; no DUT internal pipeline stages are modeled.
    logic [DATA_WIDTH-1:0] expected_pipe0 [0:PIPELINE_DELAY-1];
    logic [DATA_WIDTH-1:0] expected_pipe1 [0:PIPELINE_DELAY-1];
    logic [DATA_WIDTH-1:0] expected_pipe2 [0:PIPELINE_DELAY-1];
    bit                    expected_valid [0:PIPELINE_DELAY-1];

    int unsigned samples_captured;


    //==========================================================================
    // Coverage Tracking
    //==========================================================================

    bit reset_covered;
    bit signed_kernel_covered;
    bit high_unsigned_pixel_covered;
    bit no_saturation_covered;
    bit low_saturation_covered;
    bit high_saturation_covered;

    bit output_checked [0:2];
    bit kernel_position_covered [0:8];


    //==========================================================================
    // DUT Instance
    //==========================================================================

    conv_core #(
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk          (clk),
        .resetb       (resetb),

        .input_pixel0 (input_pixel0),
        .input_pixel1 (input_pixel1),
        .input_pixel2 (input_pixel2),
        .input_pixel3 (input_pixel3),
        .input_pixel4 (input_pixel4),

        .kernel       (kernel),

        .data_out0    (data_out0),
        .data_out1    (data_out1),
        .data_out2    (data_out2)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end


    //==========================================================================
    // Reference Functions
    //==========================================================================

    //--------------------------------------------------------------------------
    // Apply the mathematical post-processing used by the project.
    //
    //   y1    = y_conv + 128
    //   y2    = (y1 - 128) * 2 + 128
    //         = 2*y_conv + 128
    //   y_out = min(255, max(0, y2))
    //--------------------------------------------------------------------------

    function automatic logic [DATA_WIDTH-1:0] post_process_ref(
        input int signed conv_value
    );
        int signed processed_value;

        begin
            processed_value = (2 * conv_value) + 128;

            if (processed_value < 0)
                post_process_ref = '0;
            else if (processed_value > 255)
                post_process_ref = {DATA_WIDTH{1'b1}};
            else
                post_process_ref = processed_value[DATA_WIDTH-1:0];
        end
    endfunction


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
    // Print test banner.
    //--------------------------------------------------------------------------

    task automatic print_banner(
        input string test_name
    );
        begin
            $display("");
            $display("================================================================");
            $display("START TEST: %s", test_name);
            $display("TIME      : %0t", $time);
            $display("================================================================");
        end
    endtask


    //--------------------------------------------------------------------------
    // Clear all reference-model pipeline and history state.
    //--------------------------------------------------------------------------

    task automatic clear_reference;
        int row_idx;
        int col_idx;
        int pipe_idx;

        begin
            samples_captured = 0;

            for (row_idx = 0; row_idx < 5; row_idx = row_idx + 1) begin
                for (col_idx = 0; col_idx < 3; col_idx = col_idx + 1)
                    row_history[row_idx][col_idx] = 0;
            end

            for (pipe_idx = 0;
                 pipe_idx < PIPELINE_DELAY;
                 pipe_idx = pipe_idx + 1) begin

                expected_pipe0[pipe_idx] = '0;
                expected_pipe1[pipe_idx] = '0;
                expected_pipe2[pipe_idx] = '0;
                expected_valid[pipe_idx] = 1'b0;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Set all five input-row pixels.
    // This task contains no synchronization; call sync() separately before
    // changing stimulus.
    //--------------------------------------------------------------------------

    task automatic set_pixels(
        input int unsigned p0,
        input int unsigned p1,
        input int unsigned p2,
        input int unsigned p3,
        input int unsigned p4
    );
        begin
            input_pixel0 = p0[DATA_WIDTH-1:0];
            input_pixel1 = p1[DATA_WIDTH-1:0];
            input_pixel2 = p2[DATA_WIDTH-1:0];
            input_pixel3 = p3[DATA_WIDTH-1:0];
            input_pixel4 = p4[DATA_WIDTH-1:0];

            if ((p0 > 127) || (p1 > 127) || (p2 > 127) ||
                (p3 > 127) || (p4 > 127))
                high_unsigned_pixel_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Program all nine kernel coefficients and update the independent integer
    // copy used by the golden model.
    // This task contains no synchronization.
    //--------------------------------------------------------------------------

    task automatic set_kernel(
        input int signed k0,
        input int signed k1,
        input int signed k2,
        input int signed k3,
        input int signed k4,
        input int signed k5,
        input int signed k6,
        input int signed k7,
        input int signed k8
    );
        int signed values [0:8];
        int idx;

        begin
            values[0] = k0;
            values[1] = k1;
            values[2] = k2;
            values[3] = k3;
            values[4] = k4;
            values[5] = k5;
            values[6] = k6;
            values[7] = k7;
            values[8] = k8;

            for (idx = 0; idx < 9; idx = idx + 1) begin
                kernel[idx]     = values[idx];
                ref_kernel[idx] = values[idx];

                if (values[idx] < 0)
                    signed_kernel_covered = 1'b1;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Program a kernel with a single coefficient equal to +1.
    // Used to independently verify all nine spatial kernel positions.
    //--------------------------------------------------------------------------

    task automatic set_single_tap_kernel(
        input int unsigned active_index
    );
        int idx;

        begin
            for (idx = 0; idx < 9; idx = idx + 1) begin
                if (idx == active_index) begin
                    kernel[idx]     = 1;
                    ref_kernel[idx] = 1;
                end
                else begin
                    kernel[idx]     = 0;
                    ref_kernel[idx] = 0;
                end
            end

            kernel_position_covered[active_index] = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Check asynchronous reset outputs.
    //--------------------------------------------------------------------------

    task automatic check_reset_outputs;
        begin
            check_count = check_count + 3;

            assert (data_out0 === '0)
            else begin
                error_count = error_count + 1;
                $error("Reset mismatch: data_out0 expected 0, got %0d", data_out0);
            end

            assert (data_out1 === '0)
            else begin
                error_count = error_count + 1;
                $error("Reset mismatch: data_out1 expected 0, got %0d", data_out1);
            end

            assert (data_out2 === '0)
            else begin
                error_count = error_count + 1;
                $error("Reset mismatch: data_out2 expected 0, got %0d", data_out2);
            end

            reset_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Check the DUT output for the current clock edge, then update the
    // independent mathematical reference model with the five pixels captured
    // on that edge.
    //
    // Important: this task models only the external latency. It does not model
    // PE multipliers, PE partial sums, or conv_core internal grouping.
    //--------------------------------------------------------------------------

    task automatic check_and_update_reference;
        int signed conv0;
        int signed conv1;
        int signed conv2;

        int signed processed0;
        int signed processed1;
        int signed processed2;

        logic [DATA_WIDTH-1:0] next_expected0;
        logic [DATA_WIDTH-1:0] next_expected1;
        logic [DATA_WIDTH-1:0] next_expected2;

        bit next_valid;
        int pipe_idx;

        begin
            //------------------------------------------------------------------
            // Check the result that should emerge from the pipeline now.
            //------------------------------------------------------------------

            if (expected_valid[PIPELINE_DELAY-1]) begin
                check_count = check_count + 3;

                assert (data_out0 === expected_pipe0[PIPELINE_DELAY-1])
                else begin
                    error_count = error_count + 1;
                    $error(
                        "data_out0 mismatch: expected=%0d got=%0d",
                        expected_pipe0[PIPELINE_DELAY-1],
                        data_out0
                    );
                end

                assert (data_out1 === expected_pipe1[PIPELINE_DELAY-1])
                else begin
                    error_count = error_count + 1;
                    $error(
                        "data_out1 mismatch: expected=%0d got=%0d",
                        expected_pipe1[PIPELINE_DELAY-1],
                        data_out1
                    );
                end

                assert (data_out2 === expected_pipe2[PIPELINE_DELAY-1])
                else begin
                    error_count = error_count + 1;
                    $error(
                        "data_out2 mismatch: expected=%0d got=%0d",
                        expected_pipe2[PIPELINE_DELAY-1],
                        data_out2
                    );
                end

                output_checked[0] = 1'b1;
                output_checked[1] = 1'b1;
                output_checked[2] = 1'b1;
            end


            //------------------------------------------------------------------
            // Update the independent three-pixel history for each input row.
            //------------------------------------------------------------------

            row_history[0][0] = row_history[0][1];
            row_history[0][1] = row_history[0][2];
            row_history[0][2] = input_pixel0;

            row_history[1][0] = row_history[1][1];
            row_history[1][1] = row_history[1][2];
            row_history[1][2] = input_pixel1;

            row_history[2][0] = row_history[2][1];
            row_history[2][1] = row_history[2][2];
            row_history[2][2] = input_pixel2;

            row_history[3][0] = row_history[3][1];
            row_history[3][1] = row_history[3][2];
            row_history[3][2] = input_pixel3;

            row_history[4][0] = row_history[4][1];
            row_history[4][1] = row_history[4][2];
            row_history[4][2] = input_pixel4;

            samples_captured = samples_captured + 1;
            next_valid = (samples_captured >= 3);


            //------------------------------------------------------------------
            // Direct mathematical 3x3 convolution.
            //
            // Each expression contains all nine products explicitly and does
            // not follow the DUT's three-PE partial-sum architecture.
            //------------------------------------------------------------------

            conv0 =
                row_history[0][0] * ref_kernel[0] +
                row_history[0][1] * ref_kernel[1] +
                row_history[0][2] * ref_kernel[2] +
                row_history[1][0] * ref_kernel[3] +
                row_history[1][1] * ref_kernel[4] +
                row_history[1][2] * ref_kernel[5] +
                row_history[2][0] * ref_kernel[6] +
                row_history[2][1] * ref_kernel[7] +
                row_history[2][2] * ref_kernel[8];

            conv1 =
                row_history[1][0] * ref_kernel[0] +
                row_history[1][1] * ref_kernel[1] +
                row_history[1][2] * ref_kernel[2] +
                row_history[2][0] * ref_kernel[3] +
                row_history[2][1] * ref_kernel[4] +
                row_history[2][2] * ref_kernel[5] +
                row_history[3][0] * ref_kernel[6] +
                row_history[3][1] * ref_kernel[7] +
                row_history[3][2] * ref_kernel[8];

            conv2 =
                row_history[2][0] * ref_kernel[0] +
                row_history[2][1] * ref_kernel[1] +
                row_history[2][2] * ref_kernel[2] +
                row_history[3][0] * ref_kernel[3] +
                row_history[3][1] * ref_kernel[4] +
                row_history[3][2] * ref_kernel[5] +
                row_history[4][0] * ref_kernel[6] +
                row_history[4][1] * ref_kernel[7] +
                row_history[4][2] * ref_kernel[8];

            next_expected0 = post_process_ref(conv0);
            next_expected1 = post_process_ref(conv1);
            next_expected2 = post_process_ref(conv2);


            //------------------------------------------------------------------
            // Functional coverage for the post-processing result classes.
            //------------------------------------------------------------------

            if (next_valid) begin
                processed0 = (2 * conv0) + 128;
                processed1 = (2 * conv1) + 128;
                processed2 = (2 * conv2) + 128;

                if ((processed0 < 0) || (processed1 < 0) || (processed2 < 0))
                    low_saturation_covered = 1'b1;

                if ((processed0 > 255) || (processed1 > 255) || (processed2 > 255))
                    high_saturation_covered = 1'b1;

                if (((processed0 >= 0) && (processed0 <= 255)) ||
                    ((processed1 >= 0) && (processed1 <= 255)) ||
                    ((processed2 >= 0) && (processed2 <= 255)))
                    no_saturation_covered = 1'b1;
            end


            //------------------------------------------------------------------
            // Advance the expected-output latency pipeline.
            //------------------------------------------------------------------

            for (pipe_idx = PIPELINE_DELAY-1;
                 pipe_idx > 0;
                 pipe_idx = pipe_idx - 1) begin

                expected_pipe0[pipe_idx] = expected_pipe0[pipe_idx-1];
                expected_pipe1[pipe_idx] = expected_pipe1[pipe_idx-1];
                expected_pipe2[pipe_idx] = expected_pipe2[pipe_idx-1];
                expected_valid[pipe_idx] = expected_valid[pipe_idx-1];
            end

            expected_pipe0[0] = next_expected0;
            expected_pipe1[0] = next_expected1;
            expected_pipe2[0] = next_expected2;
            expected_valid[0] = next_valid;
        end
    endtask


    //==========================================================================
    // Test Sequence
    //==========================================================================

    initial begin : test_sequence
        int cycle;
        int tap;
        int idx;

        //---------------------------------------------------------------------
        // Initial values
        //---------------------------------------------------------------------

        error_count = 0;
        check_count = 0;

        reset_covered               = 1'b0;
        signed_kernel_covered       = 1'b0;
        high_unsigned_pixel_covered = 1'b0;
        no_saturation_covered       = 1'b0;
        low_saturation_covered      = 1'b0;
        high_saturation_covered     = 1'b0;

        for (idx = 0; idx < 3; idx = idx + 1)
            output_checked[idx] = 1'b0;

        for (idx = 0; idx < 9; idx = idx + 1)
            kernel_position_covered[idx] = 1'b0;

        resetb = 1'b0;

        input_pixel0 = '0;
        input_pixel1 = '0;
        input_pixel2 = '0;
        input_pixel3 = '0;
        input_pixel4 = '0;

        for (idx = 0; idx < 9; idx = idx + 1) begin
            kernel[idx] = '0;
            ref_kernel[idx] = 0;
        end

        clear_reference();


        //=====================================================================
        // TEST 1: Initial reset and asynchronous reset behavior
        //=====================================================================

        print_banner("Reset behavior");

        #1ps;
        check_reset_outputs();

        // Deassert reset synchronously with the testbench convention.
        sync();
        resetb = 1'b1;

        // Program a simple kernel and generate activity so outputs become
        // nonzero before asserting reset asynchronously.
        set_kernel(
             0,  0,  0,
             0,  1,  0,
             0,  0,  0
        );
        set_pixels(5, 10, 15, 20, 25);

        for (cycle = 0; cycle < 7; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();

            set_pixels(
                5  + cycle,
                10 + cycle,
                15 + cycle,
                20 + cycle,
                25 + cycle
            );
        end

        // Assert reset between clock edges to verify asynchronous clearing.
        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        clear_reference();
        #1ps;
        check_reset_outputs();


        //=====================================================================
        // TEST 2: Project edge-detection kernel with signed coefficients
        //=====================================================================

        print_banner("Signed project kernel [-1 -1 -1; -1 8 -1; -1 -1 -1]");

        sync();
        resetb = 1'b1;

        set_kernel(
            -1, -1, -1,
            -1,  8, -1,
            -1, -1, -1
        );
        set_pixels(10, 20, 30, 40, 50);

        for (cycle = 0; cycle < 12; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();

            set_pixels(
                10 + (cycle * 2),
                20 + (cycle * 3),
                30 + (cycle * 4),
                40 + (cycle * 5),
                50 + (cycle * 6)
            );
        end

        // Flush the last valid expected results through the output pipeline.
        for (cycle = 0; cycle < PIPELINE_DELAY; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(0, 0, 0, 0, 0);
        end


        //=====================================================================
        // TEST 3: High unsigned pixels with negative kernel coefficients
        //=====================================================================

        print_banner("Unsigned pixels above 127 with negative coefficients");

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        clear_reference();
        #1ps;
        check_reset_outputs();

        sync();
        resetb = 1'b1;

        set_kernel(
            -1,  0,  0,
             0,  1,  0,
             0,  0,  0
        );
        set_pixels(200, 210, 220, 230, 240);

        for (cycle = 0; cycle < 9; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();

            set_pixels(
                200 + (cycle % 20),
                210 + (cycle % 20),
                220 + (cycle % 20),
                230 + (cycle % 20),
                240 + (cycle % 15)
            );
        end

        for (cycle = 0; cycle < PIPELINE_DELAY; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(0, 0, 0, 0, 0);
        end


        //=====================================================================
        // TEST 4: Explicit upper saturation
        //=====================================================================

        print_banner("Upper saturation to 255");

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        clear_reference();
        #1ps;
        check_reset_outputs();

        sync();
        resetb = 1'b1;

        set_kernel(
             1, 1, 1,
             1, 1, 1,
             1, 1, 1
        );
        set_pixels(50, 60, 70, 80, 90);

        for (cycle = 0; cycle < 7; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(50, 60, 70, 80, 90);
        end

        for (cycle = 0; cycle < PIPELINE_DELAY; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(0, 0, 0, 0, 0);
        end


        //=====================================================================
        // TEST 5: Explicit lower saturation
        //=====================================================================

        print_banner("Lower saturation to 0");

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        clear_reference();
        #1ps;
        check_reset_outputs();

        sync();
        resetb = 1'b1;

        set_kernel(
            -1, -1, -1,
            -1, -1, -1,
            -1, -1, -1
        );
        set_pixels(20, 30, 40, 50, 60);

        for (cycle = 0; cycle < 7; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(20, 30, 40, 50, 60);
        end

        for (cycle = 0; cycle < PIPELINE_DELAY; cycle = cycle + 1) begin
            sync();
            check_and_update_reference();
            set_pixels(0, 0, 0, 0, 0);
        end


        //=====================================================================
        // TEST 6: Every kernel position independently
        //
        // A one-tap kernel is moved through all nine positions. Distinct row
        // and column values make a routing error observable at the outputs.
        //=====================================================================

        print_banner("All nine kernel positions");

        for (tap = 0; tap < 9; tap = tap + 1) begin

            #(CLK_PERIOD / 4);
            resetb = 1'b0;
            clear_reference();
            #1ps;
            check_reset_outputs();

            sync();
            resetb = 1'b1;

            set_single_tap_kernel(tap);
            set_pixels(3, 7, 11, 15, 19);

            for (cycle = 0; cycle < 7; cycle = cycle + 1) begin
                sync();
                check_and_update_reference();

                // Distinct horizontal progression in every row.
                set_pixels(
                    3  + cycle,
                    17 + (2 * cycle),
                    31 + (3 * cycle),
                    45 + (4 * cycle),
                    59 + (5 * cycle)
                );
            end

            for (cycle = 0; cycle < PIPELINE_DELAY; cycle = cycle + 1) begin
                sync();
                check_and_update_reference();
                set_pixels(0, 0, 0, 0, 0);
            end
        end


        //=====================================================================
        // Coverage Checks
        //=====================================================================

        $display("");
        $display("================================================================");
        $display("COVERAGE CHECK");
        $display("================================================================");

        check_count = check_count + 1;
        assert (reset_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: asynchronous reset");
        end

        check_count = check_count + 1;
        assert (signed_kernel_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: negative kernel coefficient");
        end

        check_count = check_count + 1;
        assert (high_unsigned_pixel_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: input pixel above 127");
        end

        check_count = check_count + 1;
        assert (no_saturation_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: result inside 0..255");
        end

        check_count = check_count + 1;
        assert (low_saturation_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: lower saturation");
        end

        check_count = check_count + 1;
        assert (high_saturation_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage missing: upper saturation");
        end

        for (idx = 0; idx < 3; idx = idx + 1) begin
            check_count = check_count + 1;
            assert (output_checked[idx])
            else begin
                error_count = error_count + 1;
                $error("Coverage missing: data_out%0d was not checked", idx);
            end
        end

        for (idx = 0; idx < 9; idx = idx + 1) begin
            check_count = check_count + 1;
            assert (kernel_position_covered[idx])
            else begin
                error_count = error_count + 1;
                $error("Coverage missing: kernel position %0d", idx);
            end
        end


        //=====================================================================
        // Final Result
        //=====================================================================

        $display("");
        $display("================================================================");
        $display("TEST SUMMARY");
        $display("Checks : %0d", check_count);
        $display("Errors : %0d", error_count);

        if (error_count == 0)
            $display("RESULT : PASS");
        else
            $display("RESULT : FAIL");

        $display("================================================================");

        $finish;
    end

endmodule
