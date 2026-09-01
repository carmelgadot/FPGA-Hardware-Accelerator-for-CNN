`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : tb_processing_unit

  Description :
    End-to-end integration testbench for processing_unit.

    The complete path is verified:

        input stream
            -> input row buffers
            -> conv_core
            -> output ping-pong buffers
            -> read_data / out_valid

  Independent golden-model methodology:
    - The golden model does NOT reproduce the row-buffer FSM, circular-buffer
      mapping, PE hierarchy, conv_valid shift registers, output-buffer FSM,
      address counters, or ping-pong implementation.
    - A small padded 5-row image is stored directly in a testbench array.
    - Expected results are calculated from the mathematical 3x3 convolution
      definition using all nine products.
    - The expected output transactions are then compared only with the external
      read_data values when out_valid is asserted.

  Test configuration:
    - Original image width : 4 pixels
    - Horizontal padding   : one zero on each side
    - INPUT_ROW_LENGTH     : 6 samples
    - OUTPUT_LENGTH        : 4 results
    - Active input rows    : 5
    - Parallel outputs     : 3
    - Kernel               : center-tap identity kernel

    With five active rows, the three parallel output lanes correspond to:
      lane 0 -> input rows 0..2
      lane 1 -> input rows 1..3
      lane 2 -> input rows 2..4

  Test goals:
    - Verify asynchronous reset behavior.
    - Verify that no output appears before a full valid convolution set exists.
    - Verify exactly OUTPUT_LENGTH conv_valid pulses for one padded row scan.
    - Verify mathematical horizontal-padding alignment.
    - Verify the three vertical parallel output lanes.
    - Verify end-to-end storage/readback through output_subsystem.
    - Verify output ordering and absence of duplicated/lost transactions.

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes occur only after sync() returns.
    - resetb deassertion occurs only after sync().
    - resetb assertion is intentionally asynchronous.
*/
//==============================================================================

module tb_processing_unit;

    //==========================================================================
    // Testbench Parameters
    //==========================================================================

    localparam int DATA_WIDTH               = 8;

    localparam int IMAGE_WIDTH              = 4;
    localparam int KERNEL_WIDTH             = 3;
    localparam int INPUT_ROW_LENGTH         = IMAGE_WIDTH + KERNEL_WIDTH - 1;
    localparam int OUTPUT_LENGTH            = IMAGE_WIDTH;
    localparam int ADDR_WIDTH               = 10;

    localparam int ROW_CNT_W                = 3;
    localparam int INIT_ROWS                = 5;
    localparam int STRIDE                   = 3;
    localparam int NUM_INPUT_BUFFERS        = 16;
    localparam int OCC_CNT_W                = 5;

    localparam int INPUT_BRAM_READ_LATENCY  = 2;
    localparam int CONV_CORE_LATENCY        = 3;

    localparam int NUM_OUTPUT_BUFFERS       = 6;
    localparam int PARALLEL_OUTPUTS         = 3;
    localparam int OUTPUT_BRAM_READ_LATENCY = 2;

    localparam int EXPECTED_TRANSACTIONS    = OUTPUT_LENGTH;

    localparam int TEST4_IMAGE_HEIGHT         = 4;
    localparam int TEST4_INPUT_ROWS           = TEST4_IMAGE_HEIGHT + 2;
    localparam int TEST4_OUTPUT_GROUPS        =
        (TEST4_IMAGE_HEIGHT + STRIDE - 1) / STRIDE;
    localparam int TEST4_FRAME_TRANSACTIONS   =
        TEST4_OUTPUT_GROUPS * OUTPUT_LENGTH;
    localparam int TEST4_EXPECTED_TRANSACTIONS =
        2 * TEST4_FRAME_TRANSACTIONS;

    localparam logic [INIT_ROWS-1:0] TEST4_FINAL_PADDING =
        {{(INIT_ROWS-STRIDE){1'b1}}, {STRIDE{1'b0}}};

    localparam time CLK_PERIOD = 10ns;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;

    logic                         data_valid;
    logic                         frame_done;
    logic [DATA_WIDTH-1:0]        data;

    logic signed [DATA_WIDTH-1:0] kernel [0:8];

    logic [DATA_WIDTH-1:0]        read_data [0:PARALLEL_OUTPUTS-1];
    logic                         out_valid;


    //==========================================================================
    // Independent Golden Model
    //==========================================================================

    int unsigned padded_image [0:INIT_ROWS-1][0:INPUT_ROW_LENGTH-1];
    int signed   kernel_ref   [0:8];

    logic [DATA_WIDTH-1:0] expected_lane0 [0:OUTPUT_LENGTH-1];
    logic [DATA_WIDTH-1:0] expected_lane1 [0:OUTPUT_LENGTH-1];
    logic [DATA_WIDTH-1:0] expected_lane2 [0:OUTPUT_LENGTH-1];

    int unsigned received_count;
    int unsigned conv_valid_count;
    int unsigned test4_received_count;


    //==========================================================================
    // Test Status / Coverage
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;

    bit async_reset_covered;
    bit horizontal_padding_covered;
    bit three_parallel_lanes_covered;
    bit conv_valid_count_covered;
    bit conv_data_alignment_covered;
    bit output_order_covered;
    bit no_early_output_covered;
    bit complete_end_to_end_covered;

    bit test4_active;
    bit test4_padding_zero_covered;
    bit test4_last_window_covered;
    bit test4_frame_switch_covered;
    bit test4_padding_cleared_covered;
    bit test4_next_frame_covered;
    bit test4_end_to_end_covered;


    //==========================================================================
    // DUT
    //==========================================================================

    processing_unit #(
        .DATA_WIDTH               (DATA_WIDTH),

        .INPUT_ROW_LENGTH         (INPUT_ROW_LENGTH),
        .OUTPUT_LENGTH            (OUTPUT_LENGTH),
        .ADDR_WIDTH               (ADDR_WIDTH),

        .ROW_CNT_W                (ROW_CNT_W),
        .INIT_ROWS                (INIT_ROWS),
        .STRIDE                   (STRIDE),
        .NUM_INPUT_BUFFERS        (NUM_INPUT_BUFFERS),
        .OCC_CNT_W                (OCC_CNT_W),

        .KERNEL_WIDTH             (KERNEL_WIDTH),
        .INPUT_BRAM_READ_LATENCY  (INPUT_BRAM_READ_LATENCY),
        .CONV_CORE_LATENCY        (CONV_CORE_LATENCY),

        .NUM_OUTPUT_BUFFERS       (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS         (PARALLEL_OUTPUTS),
        .OUTPUT_BRAM_READ_LATENCY (OUTPUT_BRAM_READ_LATENCY)
    ) dut (
        .clk        (clk),
        .resetb     (resetb),

        .data_valid (data_valid),
        .frame_done (frame_done),
        .data       (data),

        .kernel     (kernel),

        .read_data  (read_data),
        .out_valid  (out_valid)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end


    //==========================================================================
    // Synchronization Task
    //==========================================================================

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //==========================================================================
    // Independent Mathematical Reference Functions
    //==========================================================================

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


    //----------------------------------------------------------------------
    // Direct mathematical 3x3 convolution for one output lane/column.
    //
    // No PE grouping or DUT internal arithmetic structure is reproduced.
    //----------------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] reference_output(
        input int unsigned lane,
        input int unsigned out_col
    );
        int signed conv_sum;
        int unsigned kr;
        int unsigned kc;
        int unsigned image_row;
        int unsigned image_col;
        int unsigned kernel_idx;

        begin
            conv_sum = 0;

            for (kr = 0; kr < KERNEL_WIDTH; kr = kr + 1) begin
                for (kc = 0; kc < KERNEL_WIDTH; kc = kc + 1) begin
                    image_row = lane + kr;
                    image_col = out_col + kc;
                    kernel_idx = (kr * KERNEL_WIDTH) + kc;

                    conv_sum = conv_sum +
                               (padded_image[image_row][image_col] *
                                kernel_ref[kernel_idx]);
                end
            end

            reference_output = post_process_ref(conv_sum);
        end
    endfunction


    //----------------------------------------------------------------------
    // TEST 4 expected output for two padded frames.
    //
    // HPS supplies one zero row above and below the image and one zero pixel
    // on each side. Each processing window produces STRIDE output rows.
    // Output lanes beyond the original image height are still generated by
    // hardware and correspond to zero-valued padded input.
    //----------------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] test4_expected_output(
        input int unsigned transaction,
        input int unsigned lane
    );
        int unsigned frame_idx;
        int unsigned frame_transaction;
        int unsigned group_idx;
        int unsigned out_col;
        int unsigned image_row;
        int unsigned source_pixel;
        int unsigned first_value;

        begin
            frame_idx = transaction / TEST4_FRAME_TRANSACTIONS;
            frame_transaction = transaction % TEST4_FRAME_TRANSACTIONS;
            group_idx = frame_transaction / OUTPUT_LENGTH;
            out_col = frame_transaction % OUTPUT_LENGTH;
            image_row = (group_idx * STRIDE) + lane;

            first_value = (frame_idx == 0) ? 1 : 101;
            source_pixel = 0;

            if (image_row < TEST4_IMAGE_HEIGHT)
                source_pixel =
                    first_value +
                    (image_row * IMAGE_WIDTH) +
                    out_col;

            test4_expected_output = post_process_ref(source_pixel);
        end
    endfunction


    //==========================================================================
    // Golden-Model Setup
    //==========================================================================

    task automatic initialize_image_and_kernel;
        int row;
        int col;
        int idx;

        begin
            //------------------------------------------------------------------
            // Five rows, each with one horizontal zero on each side.
            //
            // row0: 0,  1,  2,  3,  4, 0
            // row1: 0,  5,  6,  7,  8, 0
            // row2: 0,  9, 10, 11, 12, 0
            // row3: 0, 13, 14, 15, 16, 0
            // row4: 0, 17, 18, 19, 20, 0
            //------------------------------------------------------------------

            for (row = 0; row < INIT_ROWS; row = row + 1) begin
                padded_image[row][0] = 0;

                for (col = 0; col < IMAGE_WIDTH; col = col + 1)
                    padded_image[row][col + 1] =
                        (row * IMAGE_WIDTH) + col + 1;

                padded_image[row][INPUT_ROW_LENGTH-1] = 0;
            end

            //------------------------------------------------------------------
            // Identity center tap:
            //
            //   0 0 0
            //   0 1 0
            //   0 0 0
            //------------------------------------------------------------------

            for (idx = 0; idx < 9; idx = idx + 1) begin
                kernel[idx]     = '0;
                kernel_ref[idx] = 0;
            end

            kernel[4]     = 1;
            kernel_ref[4] = 1;

            //------------------------------------------------------------------
            // Build external expected transaction sequence.
            //------------------------------------------------------------------

            for (col = 0; col < OUTPUT_LENGTH; col = col + 1) begin
                expected_lane0[col] = reference_output(0, col);
                expected_lane1[col] = reference_output(1, col);
                expected_lane2[col] = reference_output(2, col);
            end

            horizontal_padding_covered = 1'b1;
            three_parallel_lanes_covered = 1'b1;
        end
    endtask


    //==========================================================================
    // Input Stream Driver
    //==========================================================================

    task automatic stream_initial_five_rows;
        int row;
        int col;

        begin
            // Begin changing normal stimulus only after sync().
            sync();
            data_valid = 1'b1;

            for (row = 0; row < INIT_ROWS; row = row + 1) begin
                for (col = 0; col < INPUT_ROW_LENGTH; col = col + 1) begin
                    data = padded_image[row][col][DATA_WIDTH-1:0];
                    sync();
                end
            end

            data_valid = 1'b0;
            data       = '0;
        end
    endtask


    //--------------------------------------------------------------------------
    // TEST 4 checks for the current clock cycle.
    //--------------------------------------------------------------------------
    task automatic observe_test4_cycle;
        int row_idx;
        int lane_idx;

        begin
            if (resetb) begin

                if (dut.input_sample_valid &&
                    (|dut.u_input_subsystem.u_row_buffer_controller.row_padding)) begin

                    for (row_idx = 0; row_idx < INIT_ROWS; row_idx = row_idx + 1) begin
                        if (dut.u_input_subsystem.u_row_buffer_controller.row_padding[row_idx]) begin
                            check_count = check_count + 1;

                            if (dut.pixel_out[row_idx] !== '0) begin
                                $error(
                                    "[%0t] TEST 4 padding row %0d is not zero: got=%0d",
                                    $time,
                                    row_idx,
                                    dut.pixel_out[row_idx]
                                );
                                error_count = error_count + 1;
                            end
                            else
                                test4_padding_zero_covered = 1'b1;
                        end
                    end
                end

                if (dut.u_input_subsystem.u_row_buffer_controller.last_window) begin
                    test4_last_window_covered = 1'b1;

                    check_count = check_count + 1;
                    if (dut.u_input_subsystem.u_row_buffer_controller.row_padding !==
                        TEST4_FINAL_PADDING) begin
                        $error(
                            "[%0t] TEST 4 final window padding mismatch: expected=%b got=%b",
                            $time,
                            TEST4_FINAL_PADDING,
                            dut.u_input_subsystem.u_row_buffer_controller.row_padding
                        );
                        error_count = error_count + 1;
                    end
                end

                if (dut.u_input_subsystem.u_row_buffer_controller.frame_switch) begin
                    if (!test4_last_window_covered) begin
                        $error(
                            "[%0t] TEST 4 frame_switch occurred before final window",
                            $time
                        );
                        error_count = error_count + 1;
                    end

                    test4_frame_switch_covered = 1'b1;
                end

                if (test4_frame_switch_covered &&
                    !dut.u_input_subsystem.u_row_buffer_controller.frame_switch &&
                    (dut.u_input_subsystem.u_row_buffer_controller.row_padding == '0))
                    test4_padding_cleared_covered = 1'b1;

                if (out_valid) begin

                    if (test4_received_count >= TEST4_EXPECTED_TRANSACTIONS) begin
                        $error("[%0t] TEST 4 unexpected extra output transaction", $time);
                        error_count = error_count + 1;
                    end
                    else begin
                        check_count = check_count + PARALLEL_OUTPUTS;

                        for (lane_idx = 0;
                             lane_idx < PARALLEL_OUTPUTS;
                             lane_idx = lane_idx + 1) begin

                            if (read_data[lane_idx] !==
                                test4_expected_output(
                                    test4_received_count,
                                    lane_idx
                                )) begin

                                $error(
                                    "[%0t] TEST 4 output mismatch: transaction=%0d lane=%0d expected=%0d got=%0d",
                                    $time,
                                    test4_received_count,
                                    lane_idx,
                                    test4_expected_output(
                                        test4_received_count,
                                        lane_idx
                                    ),
                                    read_data[lane_idx]
                                );
                                error_count = error_count + 1;
                            end
                        end

                        if (test4_received_count >= TEST4_FRAME_TRANSACTIONS)
                            test4_next_frame_covered = 1'b1;
                    end

                    test4_received_count = test4_received_count + 1;
                end
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // TEST 4 frame driver.
    //
    // The stream models the HPS output exactly: one full zero row above and
    // below the image and one zero pixel on each side of every image row.
    //--------------------------------------------------------------------------
    task automatic stream_test4_frame(
        input int unsigned first_value
    );
        int row;
        int col;
        int unsigned pixel_value;

        begin
            sync();
            observe_test4_cycle();
            data_valid = 1'b1;

            for (row = 0; row < TEST4_INPUT_ROWS; row = row + 1) begin
                for (col = 0; col < INPUT_ROW_LENGTH; col = col + 1) begin

                    if ((row == 0) ||
                        (row == TEST4_INPUT_ROWS-1) ||
                        (col == 0) ||
                        (col == INPUT_ROW_LENGTH-1)) begin
                        pixel_value = 0;
                    end
                    else begin
                        pixel_value =
                            first_value +
                            ((row - 1) * IMAGE_WIDTH) +
                            (col - 1);
                    end

                    data = pixel_value[DATA_WIDTH-1:0];

                    if ((row == TEST4_INPUT_ROWS-1) &&
                        (col == INPUT_ROW_LENGTH-1))
                        frame_done = 1'b1;

                    sync();
                    observe_test4_cycle();

                    if (frame_done)
                        frame_done = 1'b0;
                end
            end

            data_valid = 1'b0;
            data       = '0;
        end
    endtask


    //==========================================================================
    // End-to-End Output Monitor
    //==========================================================================

    always @(posedge clk) begin
        #2ps;

        if (!resetb) begin
            // Counters are testbench bookkeeping and are intentionally not
            // cleared here after the initial test has begun.
        end
        else if (!test4_active) begin

            //------------------------------------------------------------------
            // Verify conv_valid / conv_data alignment directly.
            //
            // Whenever conv_valid is asserted, the conv_core outputs must match
            // the next mathematically expected convolution transaction in the
            // same clock cycle. This catches a conv_valid pulse that is one
            // clock early or one clock late.
            //------------------------------------------------------------------
            if (dut.conv_valid) begin

                if (conv_valid_count >= OUTPUT_LENGTH) begin
                    $error("[%0t] Unexpected extra conv_valid pulse", $time);
                    error_count = error_count + 1;
                end
                else begin
                    check_count = check_count + 3;

                    if (dut.conv_data[0] !== expected_lane0[conv_valid_count]) begin
                        $error(
                            "[%0t] conv_data[0] / conv_valid misalignment at result %0d: expected=%0d got=%0d",
                            $time,
                            conv_valid_count,
                            expected_lane0[conv_valid_count],
                            dut.conv_data[0]
                        );
                        error_count = error_count + 1;
                    end

                    if (dut.conv_data[1] !== expected_lane1[conv_valid_count]) begin
                        $error(
                            "[%0t] conv_data[1] / conv_valid misalignment at result %0d: expected=%0d got=%0d",
                            $time,
                            conv_valid_count,
                            expected_lane1[conv_valid_count],
                            dut.conv_data[1]
                        );
                        error_count = error_count + 1;
                    end

                    if (dut.conv_data[2] !== expected_lane2[conv_valid_count]) begin
                        $error(
                            "[%0t] conv_data[2] / conv_valid misalignment at result %0d: expected=%0d got=%0d",
                            $time,
                            conv_valid_count,
                            expected_lane2[conv_valid_count],
                            dut.conv_data[2]
                        );
                        error_count = error_count + 1;
                    end

                    if ((dut.conv_data[0] === expected_lane0[conv_valid_count]) &&
                        (dut.conv_data[1] === expected_lane1[conv_valid_count]) &&
                        (dut.conv_data[2] === expected_lane2[conv_valid_count])) begin

                        $display(
                            "[%0t] PASS conv_valid alignment %0d : {%0d, %0d, %0d}",
                            $time,
                            conv_valid_count,
                            dut.conv_data[0],
                            dut.conv_data[1],
                            dut.conv_data[2]
                        );

                        if (conv_valid_count == OUTPUT_LENGTH-1)
                            conv_data_alignment_covered = 1'b1;
                    end
                end

                conv_valid_count = conv_valid_count + 1;
            end


            //------------------------------------------------------------------
            // External result check.
            //------------------------------------------------------------------
            if (out_valid) begin

                check_count = check_count + 1;

                if (conv_valid_count < OUTPUT_LENGTH) begin
                    $error(
                        "[%0t] out_valid asserted before a complete output group was written",
                        $time
                    );
                    error_count = error_count + 1;
                end
                else begin
                    no_early_output_covered = 1'b1;
                end

                if (received_count >= EXPECTED_TRANSACTIONS) begin
                    $error("[%0t] Unexpected extra output transaction", $time);
                    error_count = error_count + 1;
                end
                else begin

                    if (read_data[0] !== expected_lane0[received_count]) begin
                        $error(
                            "[%0t] lane0 mismatch at output %0d: expected=%0d got=%0d",
                            $time,
                            received_count,
                            expected_lane0[received_count],
                            read_data[0]
                        );
                        error_count = error_count + 1;
                    end

                    if (read_data[1] !== expected_lane1[received_count]) begin
                        $error(
                            "[%0t] lane1 mismatch at output %0d: expected=%0d got=%0d",
                            $time,
                            received_count,
                            expected_lane1[received_count],
                            read_data[1]
                        );
                        error_count = error_count + 1;
                    end

                    if (read_data[2] !== expected_lane2[received_count]) begin
                        $error(
                            "[%0t] lane2 mismatch at output %0d: expected=%0d got=%0d",
                            $time,
                            received_count,
                            expected_lane2[received_count],
                            read_data[2]
                        );
                        error_count = error_count + 1;
                    end

                    if ((read_data[0] === expected_lane0[received_count]) &&
                        (read_data[1] === expected_lane1[received_count]) &&
                        (read_data[2] === expected_lane2[received_count])) begin

                        $display(
                            "[%0t] PASS output %0d : {%0d, %0d, %0d}",
                            $time,
                            received_count,
                            read_data[0],
                            read_data[1],
                            read_data[2]
                        );
                    end
                end

                received_count = received_count + 1;
            end
        end
    end


    //==========================================================================
    // Test Sequence
    //==========================================================================

    initial begin : test_sequence
        int unsigned timeout_cycles;

        //----------------------------------------------------------------------
        // Initialization
        //----------------------------------------------------------------------
        resetb     = 1'b1;
        data_valid = 1'b0;
        frame_done = 1'b0;
        data       = '0;

        received_count   = 0;
        conv_valid_count = 0;

        error_count = 0;
        check_count = 0;

        async_reset_covered          = 1'b0;
        horizontal_padding_covered   = 1'b0;
        three_parallel_lanes_covered = 1'b0;
        conv_valid_count_covered     = 1'b0;
        conv_data_alignment_covered  = 1'b0;
        output_order_covered         = 1'b0;
        no_early_output_covered      = 1'b0;
        complete_end_to_end_covered  = 1'b0;

        test4_active                  = 1'b0;
        test4_padding_zero_covered    = 1'b0;
        test4_last_window_covered     = 1'b0;
        test4_frame_switch_covered    = 1'b0;
        test4_padding_cleared_covered = 1'b0;
        test4_next_frame_covered      = 1'b0;
        test4_end_to_end_covered      = 1'b0;
        test4_received_count          = 0;

        initialize_image_and_kernel();


        //======================================================================
        // TEST 1: Asynchronous reset
        //======================================================================

        #2.5ns;
        resetb = 1'b0;
        #1ns;

        if (out_valid !== 1'b0) begin
            $error("Asynchronous reset did not clear out_valid");
            error_count = error_count + 1;
        end

        if ((read_data[0] !== '0) ||
            (read_data[1] !== '0) ||
            (read_data[2] !== '0)) begin
            $error(
                "Asynchronous reset did not clear read_data: {%0d,%0d,%0d}",
                read_data[0],
                read_data[1],
                read_data[2]
            );
            error_count = error_count + 1;
        end

        async_reset_covered = 1'b1;

        sync();
        resetb = 1'b1;


        //======================================================================
        // TEST 2: Stream five horizontally padded rows
        //======================================================================

        stream_initial_five_rows();


        //======================================================================
        // TEST 3: Wait for complete end-to-end result
        //======================================================================

        timeout_cycles = 0;

        while ((received_count < EXPECTED_TRANSACTIONS) &&
               (timeout_cycles < 200)) begin
            sync();
            timeout_cycles = timeout_cycles + 1;
        end

        if (received_count < EXPECTED_TRANSACTIONS) begin
            $error(
                "Timeout: received %0d of %0d expected output transactions",
                received_count,
                EXPECTED_TRANSACTIONS
            );
            error_count = error_count + 1;
        end


        // Give the design extra clocks. No additional conv_valid/output
        // transaction is expected from the completed single window scan.
        repeat (12)
            sync();


        //======================================================================
        // Final Checks
        //======================================================================

        if (conv_valid_count == OUTPUT_LENGTH)
            conv_valid_count_covered = 1'b1;
        else begin
            $error(
                "conv_valid count mismatch: expected=%0d got=%0d",
                OUTPUT_LENGTH,
                conv_valid_count
            );
            error_count = error_count + 1;
        end

        if (received_count == EXPECTED_TRANSACTIONS) begin
            output_order_covered        = 1'b1;
            complete_end_to_end_covered = 1'b1;
        end
        else begin
            $error(
                "Output transaction count mismatch: expected=%0d got=%0d",
                EXPECTED_TRANSACTIONS,
                received_count
            );
            error_count = error_count + 1;
        end

        if (!async_reset_covered ||
            !horizontal_padding_covered ||
            !three_parallel_lanes_covered ||
            !conv_valid_count_covered ||
            !conv_data_alignment_covered ||
            !output_order_covered ||
            !no_early_output_covered ||
            !complete_end_to_end_covered) begin

            $error("Coverage failure: one or more integration goals were not covered");
            error_count = error_count + 1;
        end


        //======================================================================
        // TEST 4: HPS border padding, tail padding, and frame switch
        //======================================================================

        sync();
        test4_active = 1'b1;

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ns;

        test4_received_count = 0;
        data_valid = 1'b0;
        frame_done = 1'b0;
        data       = '0;

        sync();
        resetb = 1'b1;


        // FRAME 0: original image values 1..16, surrounded by HPS zero padding.
        stream_test4_frame(1);

        timeout_cycles = 0;

        while (!test4_frame_switch_covered &&
               (timeout_cycles < 400)) begin
            sync();
            observe_test4_cycle();
            timeout_cycles = timeout_cycles + 1;
        end

        if (!test4_frame_switch_covered) begin
            $error("TEST 4 timeout waiting for frame_switch");
            error_count = error_count + 1;
        end


        // FRAME 1: different values verify that no previous-frame data leaks.
        stream_test4_frame(101);

        timeout_cycles = 0;

        while ((test4_received_count < TEST4_EXPECTED_TRANSACTIONS) &&
               (timeout_cycles < 500)) begin
            sync();
            observe_test4_cycle();
            timeout_cycles = timeout_cycles + 1;
        end

        if (test4_received_count < TEST4_EXPECTED_TRANSACTIONS) begin
            $error(
                "TEST 4 timeout: received %0d of %0d expected output transactions",
                test4_received_count,
                TEST4_EXPECTED_TRANSACTIONS
            );
            error_count = error_count + 1;
        end

        repeat (12) begin
            sync();
            observe_test4_cycle();
        end

        if (test4_received_count != TEST4_EXPECTED_TRANSACTIONS) begin
            $error(
                "TEST 4 output transaction count mismatch: expected=%0d got=%0d",
                TEST4_EXPECTED_TRANSACTIONS,
                test4_received_count
            );
            error_count = error_count + 1;
        end

        if (!test4_padding_zero_covered ||
            !test4_last_window_covered ||
            !test4_frame_switch_covered ||
            !test4_padding_cleared_covered ||
            !test4_next_frame_covered) begin

            $error("TEST 4 coverage failure");
            error_count = error_count + 1;
        end
        else
            test4_end_to_end_covered = 1'b1;


        $display("");
        $display("==============================================================");
        $display("tb_processing_unit summary");
        $display("--------------------------------------------------------------");
        $display("Expected output transactions:      %0d", EXPECTED_TRANSACTIONS);
        $display("conv_valid pulses observed:        %0d", conv_valid_count);
        $display("Output transactions received:      %0d", received_count);
        $display("External checks performed:         %0d", check_count);
        $display("Async reset covered:               %0d", async_reset_covered);
        $display("Horizontal padding covered:        %0d", horizontal_padding_covered);
        $display("Three parallel lanes covered:      %0d", three_parallel_lanes_covered);
        $display("conv_valid count covered:          %0d", conv_valid_count_covered);
        $display("conv_data alignment covered:       %0d", conv_data_alignment_covered);
        $display("Output order covered:              %0d", output_order_covered);
        $display("No early output covered:           %0d", no_early_output_covered);
        $display("End-to-end path covered:           %0d", complete_end_to_end_covered);
        $display("TEST 4 output transactions:        %0d", test4_received_count);
        $display("TEST 4 padding zeros covered:      %0d", test4_padding_zero_covered);
        $display("TEST 4 final window covered:       %0d", test4_last_window_covered);
        $display("TEST 4 frame switch covered:       %0d", test4_frame_switch_covered);
        $display("TEST 4 padding cleared:            %0d", test4_padding_cleared_covered);
        $display("TEST 4 next frame covered:         %0d", test4_next_frame_covered);
        $display("TEST 4 end-to-end covered:         %0d", test4_end_to_end_covered);
        $display("Errors:                            %0d", error_count);
        $display("==============================================================");

        if (error_count == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");

        $finish;
    end


endmodule
