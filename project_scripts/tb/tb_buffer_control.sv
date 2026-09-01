`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : tb_buffer_control

  Description :
    Functional verification of the buffer_control module.

    The DUT controls the circular mapping and activation of the physical
    row buffers. It contains no pixel data path.

  General Goals :
    - Verify asynchronous reset behavior.
    - Verify the initial fill-buffer and top-buffer positions.
    - Verify that fill_buffer advances only after row_write_done.
    - Verify that top_buffer advances by STRIDE only after advance_window.
    - Verify circular wrap-around of both buffer pointers.
    - Verify generation of row_sel for all logical rows.
    - Verify correct circular logical-row mapping.
    - Verify bram_wr_en generation for every physical fill buffer.
    - Verify bram_rd_en generation for every active processing window.
    - Verify all four wr_valid / rd_valid combinations.
    - Verify independent movement of fill and top pointers.
    - Verify simultaneous movement of both pointers.
    - Verify end-of-frame padding reservation and frame switching.
    - Verify row_padding generation.
    - Verify next_row_ready and write_blocked occupancy indications.
    - Verify complete control-state coverage.

  Exhaustive Coverage :
    For NUM_BUFFERS = 16:

      fill-buffer positions = 16
      top-buffer positions  = 16
      enable combinations   = 4

      Total configurations checked:

          16 x 16 x 4 = 1024

    The test also verifies that every logical row is mapped to every physical
    BRAM at least once during the exhaustive sweep.

  Methodology :
    - Uses sync() to align stimulus to posedges, except when demonstrating async-assert resetb.
    - resetb deassertion is performed only after sync().
    - Uses assertions for automatic pass/fail detection.
    - Uses explicit procedural coverage tracking and checks at the end that
      every required configuration was exercised.
*/
//==============================================================================

module tb_buffer_control;

    //==========================================================================
    // Parameters
    //==========================================================================

    localparam int unsigned NUM_BUFFERS = 16;
    localparam int unsigned INIT_ROWS   = 5;
    localparam int unsigned STRIDE      = 3;
    localparam int unsigned OCC_CNT_W   = 5;

    localparam int unsigned PAD_ROWS = STRIDE - 1;

    localparam time CLK_PERIOD = 10ns;

    typedef logic [NUM_BUFFERS-1:0] mask_t;

    localparam logic [NUM_BUFFERS-1:0] ZERO_MASK =
        {NUM_BUFFERS{1'b0}};


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;

    logic row_write_done;
    logic advance_window;
    logic frame_done;
    logic frame_switch;

    logic wr_valid;
    logic rd_valid;

    logic next_row_ready;
    logic write_blocked;
    logic last_window;

    logic [NUM_BUFFERS-1:0] bram_wr_en;
    logic [NUM_BUFFERS-1:0] bram_rd_en;

    logic [NUM_BUFFERS-1:0] row_sel [0:INIT_ROWS-1];
    logic [INIT_ROWS-1:0]   row_padding;


    //==========================================================================
    // Test Status
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;


    //==========================================================================
    // Coverage Tracking
    //==========================================================================

    // Every fill/top pointer pair with every wr_valid/rd_valid combination.
    bit configuration_covered
        [0:NUM_BUFFERS-1]
        [0:NUM_BUFFERS-1]
        [0:3];

    // Every logical row must select every physical BRAM.
    bit row_route_covered
        [0:INIT_ROWS-1]
        [0:NUM_BUFFERS-1];

    // Every physical BRAM must appear as the active write buffer.
    bit write_position_covered [0:NUM_BUFFERS-1];

    // Every physical BRAM position must appear as the top of a read window.
    bit read_window_covered [0:NUM_BUFFERS-1];

    bit reset_covered;
    bit simultaneous_advance_covered;
    bit frame_done_with_row_covered;
    bit frame_done_after_row_covered;
    bit frame_switch_covered;
    bit padding_covered;
    bit last_window_two_pad_covered;
    bit last_window_one_pad_covered;
    bit last_window_zero_pad_covered;
    bit next_row_ready_covered;
    bit write_blocked_covered;


    //==========================================================================
    // DUT Instance
    //
    // Tracks the circular fill and top buffer positions, generates one-hot
    // logical-row selectors, and generates the physical BRAM read/write enables.
    //==========================================================================

    buffer_control #(
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS),
        .STRIDE      (STRIDE),
        .OCC_CNT_W   (OCC_CNT_W)
    ) dut (
        .clk            (clk),
        .resetb         (resetb),

        .row_write_done (row_write_done),
        .advance_window (advance_window),
        .frame_done     (frame_done),
        .frame_switch   (frame_switch),

        .wr_valid       (wr_valid),
        .rd_valid       (rd_valid),

        .next_row_ready (next_row_ready),
        .write_blocked  (write_blocked),
        .last_window    (last_window),

        .bram_wr_en     (bram_wr_en),
        .bram_rd_en     (bram_rd_en),

        .row_sel        (row_sel),
        .row_padding    (row_padding)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end


    //==========================================================================
    // Utility Functions
    //==========================================================================

    // Return a one-hot mask for one physical BRAM index.
    function automatic logic [NUM_BUFFERS-1:0] onehot_buffer(
        input int unsigned buffer_idx
    );
        logic [NUM_BUFFERS-1:0] result;

        begin
            result = {NUM_BUFFERS{1'b0}};
            result[buffer_idx] = 1'b1;

            onehot_buffer = result;
        end
    endfunction


    // Return the expected physical BRAM for one logical row.
    //
    // The mapping is intentionally written as an explicit reference table
    // instead of reproducing the DUT circular-mapping expression. This keeps
    // the golden model independent from the implementation under test.
    function automatic int unsigned expected_physical_buffer(
        input int unsigned top_idx,
        input int unsigned logical_row
    );
        begin
            case (top_idx)
                0:  case (logical_row) 0: expected_physical_buffer = 0;  1: expected_physical_buffer = 1;  2: expected_physical_buffer = 2;  3: expected_physical_buffer = 3;  default: expected_physical_buffer = 4;  endcase
                1:  case (logical_row) 0: expected_physical_buffer = 1;  1: expected_physical_buffer = 2;  2: expected_physical_buffer = 3;  3: expected_physical_buffer = 4;  default: expected_physical_buffer = 5;  endcase
                2:  case (logical_row) 0: expected_physical_buffer = 2;  1: expected_physical_buffer = 3;  2: expected_physical_buffer = 4;  3: expected_physical_buffer = 5;  default: expected_physical_buffer = 6;  endcase
                3:  case (logical_row) 0: expected_physical_buffer = 3;  1: expected_physical_buffer = 4;  2: expected_physical_buffer = 5;  3: expected_physical_buffer = 6;  default: expected_physical_buffer = 7;  endcase
                4:  case (logical_row) 0: expected_physical_buffer = 4;  1: expected_physical_buffer = 5;  2: expected_physical_buffer = 6;  3: expected_physical_buffer = 7;  default: expected_physical_buffer = 8;  endcase
                5:  case (logical_row) 0: expected_physical_buffer = 5;  1: expected_physical_buffer = 6;  2: expected_physical_buffer = 7;  3: expected_physical_buffer = 8;  default: expected_physical_buffer = 9;  endcase
                6:  case (logical_row) 0: expected_physical_buffer = 6;  1: expected_physical_buffer = 7;  2: expected_physical_buffer = 8;  3: expected_physical_buffer = 9;  default: expected_physical_buffer = 10; endcase
                7:  case (logical_row) 0: expected_physical_buffer = 7;  1: expected_physical_buffer = 8;  2: expected_physical_buffer = 9;  3: expected_physical_buffer = 10; default: expected_physical_buffer = 11; endcase
                8:  case (logical_row) 0: expected_physical_buffer = 8;  1: expected_physical_buffer = 9;  2: expected_physical_buffer = 10; 3: expected_physical_buffer = 11; default: expected_physical_buffer = 12; endcase
                9:  case (logical_row) 0: expected_physical_buffer = 9;  1: expected_physical_buffer = 10; 2: expected_physical_buffer = 11; 3: expected_physical_buffer = 12; default: expected_physical_buffer = 13; endcase
                10: case (logical_row) 0: expected_physical_buffer = 10; 1: expected_physical_buffer = 11; 2: expected_physical_buffer = 12; 3: expected_physical_buffer = 13; default: expected_physical_buffer = 14; endcase
                11: case (logical_row) 0: expected_physical_buffer = 11; 1: expected_physical_buffer = 12; 2: expected_physical_buffer = 13; 3: expected_physical_buffer = 14; default: expected_physical_buffer = 15; endcase
                12: case (logical_row) 0: expected_physical_buffer = 12; 1: expected_physical_buffer = 13; 2: expected_physical_buffer = 14; 3: expected_physical_buffer = 15; default: expected_physical_buffer = 0;  endcase
                13: case (logical_row) 0: expected_physical_buffer = 13; 1: expected_physical_buffer = 14; 2: expected_physical_buffer = 15; 3: expected_physical_buffer = 0;  default: expected_physical_buffer = 1;  endcase
                14: case (logical_row) 0: expected_physical_buffer = 14; 1: expected_physical_buffer = 15; 2: expected_physical_buffer = 0;  3: expected_physical_buffer = 1;  default: expected_physical_buffer = 2;  endcase
                15: case (logical_row) 0: expected_physical_buffer = 15; 1: expected_physical_buffer = 0;  2: expected_physical_buffer = 1;  3: expected_physical_buffer = 2;  default: expected_physical_buffer = 3;  endcase
                default: expected_physical_buffer = 0;
            endcase
        end
    endfunction


    // Return the expected active read mask for a given top-buffer position.
    function automatic logic [NUM_BUFFERS-1:0] expected_read_mask(
        input int unsigned top_idx
    );
        logic [NUM_BUFFERS-1:0] result;
        int unsigned logical_row;
        int unsigned physical_buffer;

        begin
            result = {NUM_BUFFERS{1'b0}};

            for (logical_row = 0;
                 logical_row < INIT_ROWS;
                 logical_row = logical_row + 1) begin

                physical_buffer =
                    expected_physical_buffer(top_idx, logical_row);

                result[physical_buffer] = 1'b1;

            end

            expected_read_mask = result;
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
    // Check the complete DUT state through its external outputs.
    //
    // fill_idx and top_idx represent the expected internal pointer positions.
    // wr_enable and rd_enable represent the current valid inputs.
    //--------------------------------------------------------------------------

    task automatic check_state(
        input int unsigned fill_idx,
        input int unsigned top_idx,
        input logic        wr_enable,
        input logic        rd_enable
    );

        logic [NUM_BUFFERS-1:0] expected_wr_en;
        logic [NUM_BUFFERS-1:0] expected_rd_en;
        logic [NUM_BUFFERS-1:0] expected_row_sel;

        int unsigned logical_row;
        int unsigned physical_buffer;
        int unsigned enable_combination;

        begin

            // Expected write enable.
            expected_wr_en = {NUM_BUFFERS{1'b0}};

            if (wr_enable)
                expected_wr_en[fill_idx] = 1'b1;


            // Expected read enables.
            expected_rd_en = {NUM_BUFFERS{1'b0}};

            if (rd_enable)
                expected_rd_en = expected_read_mask(top_idx);


            // Check physical BRAM write enables.
            check_count = check_count + 1;

            assert (bram_wr_en === expected_wr_en)
            else begin
                error_count = error_count + 1;

                $error(
                    "bram_wr_en mismatch: fill=%0d wr_valid=%0b expected=%b got=%b",
                    fill_idx,
                    wr_enable,
                    expected_wr_en,
                    bram_wr_en
                );
            end


            // Check physical BRAM read enables.
            check_count = check_count + 1;

            assert (bram_rd_en === expected_rd_en)
            else begin
                error_count = error_count + 1;

                $error(
                    "bram_rd_en mismatch: top=%0d rd_valid=%0b expected=%b got=%b",
                    top_idx,
                    rd_enable,
                    expected_rd_en,
                    bram_rd_en
                );
            end


            // Check every logical-row selector.
            for (logical_row = 0;
                 logical_row < INIT_ROWS;
                 logical_row = logical_row + 1) begin

                physical_buffer =
                    expected_physical_buffer(top_idx, logical_row);

                expected_row_sel =
                    onehot_buffer(physical_buffer);

                check_count = check_count + 1;

                assert (row_sel[logical_row] === expected_row_sel)
                else begin
                    error_count = error_count + 1;

                    $error(
                        "row_sel[%0d] mismatch: top=%0d expected BRAM%0d (%b), got=%b",
                        logical_row,
                        top_idx,
                        physical_buffer,
                        expected_row_sel,
                        row_sel[logical_row]
                    );
                end

            end


            //------------------------------------------------------------------
            // Coverage update
            //------------------------------------------------------------------

            enable_combination =
                (wr_enable ? 2 : 0) +
                (rd_enable ? 1 : 0);

            configuration_covered
                [fill_idx]
                [top_idx]
                [enable_combination] = 1'b1;


            if (wr_enable)
                write_position_covered[fill_idx] = 1'b1;


            if (rd_enable) begin

                read_window_covered[top_idx] = 1'b1;

                for (logical_row = 0;
                     logical_row < INIT_ROWS;
                     logical_row = logical_row + 1) begin

                    physical_buffer =
                        expected_physical_buffer(top_idx, logical_row);

                    row_route_covered
                        [logical_row]
                        [physical_buffer] = 1'b1;

                end

            end

        end
    endtask


    //--------------------------------------------------------------------------
    // Check the new buffer-management state.
    //
    // occupied_rows is checked hierarchically because only threshold indications
    // are exposed by the DUT.
    //--------------------------------------------------------------------------

    task automatic check_management_state(
        input int unsigned          expected_occupied_rows,
        input logic                 expected_next_row_ready,
        input logic                 expected_write_blocked,
        input logic [INIT_ROWS-1:0] expected_row_padding
    );
        begin

            check_count = check_count + 1;

            assert (dut.occupied_rows === expected_occupied_rows)
            else begin
                error_count = error_count + 1;
                $error(
                    "occupied_rows mismatch: expected=%0d got=%0d",
                    expected_occupied_rows,
                    dut.occupied_rows
                );
            end


            check_count = check_count + 1;

            assert (next_row_ready === expected_next_row_ready)
            else begin
                error_count = error_count + 1;
                $error(
                    "next_row_ready mismatch: expected=%0b got=%0b occupied_rows=%0d",
                    expected_next_row_ready,
                    next_row_ready,
                    dut.occupied_rows
                );
            end


            check_count = check_count + 1;

            assert (write_blocked === expected_write_blocked)
            else begin
                error_count = error_count + 1;
                $error(
                    "write_blocked mismatch: expected=%0b got=%0b occupied_rows=%0d",
                    expected_write_blocked,
                    write_blocked,
                    dut.occupied_rows
                );
            end


            check_count = check_count + 1;

            assert (row_padding === expected_row_padding)
            else begin
                error_count = error_count + 1;
                $error(
                    "row_padding mismatch: expected=%b got=%b",
                    expected_row_padding,
                    row_padding
                );
            end

        end
    endtask


    //--------------------------------------------------------------------------
    // Drive one wr_valid / rd_valid combination and check the complete output.
    //--------------------------------------------------------------------------

    task automatic drive_enable_combination(
        input int unsigned fill_idx,
        input int unsigned top_idx,
        input logic        wr_enable,
        input logic        rd_enable
    );
        begin

            sync();

            wr_valid = wr_enable;
            rd_valid = rd_enable;

            #1ps;

            check_state(
                fill_idx,
                top_idx,
                wr_enable,
                rd_enable
            );

        end
    endtask


    //--------------------------------------------------------------------------
    // Advance the fill-buffer pointer by one physical BRAM.
    //--------------------------------------------------------------------------

    task automatic advance_fill_pointer;
        begin

            sync();

            wr_valid       = 1'b1;
            rd_valid       = 1'b0;
            row_write_done = 1'b1;
            advance_window = 1'b0;

            sync();

            wr_valid       = 1'b0;
            row_write_done = 1'b0;

            #1ps;

        end
    endtask


    //--------------------------------------------------------------------------
    // Advance the top-buffer pointer by STRIDE physical BRAMs.
    //--------------------------------------------------------------------------

    task automatic advance_top_pointer;
        begin

            sync();

            wr_valid       = 1'b0;
            rd_valid       = 1'b0;
            row_write_done = 1'b0;
            advance_window = 1'b1;

            sync();

            advance_window = 1'b0;

        end
    endtask


    //--------------------------------------------------------------------------
    // Advance both pointers on the same clock edge.
    //--------------------------------------------------------------------------

    task automatic advance_both_pointers;
        begin

            sync();

            wr_valid       = 1'b1;
            rd_valid       = 1'b0;
            row_write_done = 1'b1;
            advance_window = 1'b1;

            sync();

            wr_valid       = 1'b0;
            row_write_done = 1'b0;
            advance_window = 1'b0;

            #1ps;

            simultaneous_advance_covered = 1'b1;

        end
    endtask


    //--------------------------------------------------------------------------
    // Check that every required coverage point was exercised.
    //--------------------------------------------------------------------------

    task automatic check_coverage;

        int unsigned fill_idx;
        int unsigned top_idx;
        int unsigned combination;
        int unsigned logical_row;
        int unsigned buffer_idx;

        int unsigned covered_configurations;
        int unsigned expected_configurations;

        begin

            covered_configurations  = 0;
            expected_configurations =
                NUM_BUFFERS * NUM_BUFFERS * 4;


            //------------------------------------------------------------------
            // Complete pointer/enables configuration coverage
            //------------------------------------------------------------------

            for (fill_idx = 0;
                 fill_idx < NUM_BUFFERS;
                 fill_idx = fill_idx + 1) begin

                for (top_idx = 0;
                     top_idx < NUM_BUFFERS;
                     top_idx = top_idx + 1) begin

                    for (combination = 0;
                         combination < 4;
                         combination = combination + 1) begin

                        if (configuration_covered
                            [fill_idx]
                            [top_idx]
                            [combination]) begin

                            covered_configurations =
                                covered_configurations + 1;

                        end
                        else begin

                            error_count = error_count + 1;

                            $error(
                                "COVERAGE FAILED: fill=%0d top=%0d enable_combination=%0d not covered",
                                fill_idx,
                                top_idx,
                                combination
                            );

                        end

                    end

                end

            end


            //------------------------------------------------------------------
            // Logical-row to physical-BRAM coverage
            //------------------------------------------------------------------

            for (logical_row = 0;
                 logical_row < INIT_ROWS;
                 logical_row = logical_row + 1) begin

                for (buffer_idx = 0;
                     buffer_idx < NUM_BUFFERS;
                     buffer_idx = buffer_idx + 1) begin

                    if (!row_route_covered
                        [logical_row]
                        [buffer_idx]) begin

                        error_count = error_count + 1;

                        $error(
                            "COVERAGE FAILED: logical row %0d never mapped to BRAM%0d",
                            logical_row,
                            buffer_idx
                        );

                    end

                end

            end


            //------------------------------------------------------------------
            // Write-buffer position coverage
            //------------------------------------------------------------------

            for (buffer_idx = 0;
                 buffer_idx < NUM_BUFFERS;
                 buffer_idx = buffer_idx + 1) begin

                if (!write_position_covered[buffer_idx]) begin

                    error_count = error_count + 1;

                    $error(
                        "COVERAGE FAILED: BRAM%0d never used as fill buffer",
                        buffer_idx
                    );

                end

            end


            //------------------------------------------------------------------
            // Active-window top position coverage
            //------------------------------------------------------------------

            for (top_idx = 0;
                 top_idx < NUM_BUFFERS;
                 top_idx = top_idx + 1) begin

                if (!read_window_covered[top_idx]) begin

                    error_count = error_count + 1;

                    $error(
                        "COVERAGE FAILED: BRAM%0d never used as top buffer",
                        top_idx
                    );

                end

            end


            //------------------------------------------------------------------
            // Special-event coverage
            //------------------------------------------------------------------

            if (!reset_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: asynchronous reset was not covered");
            end

            if (!simultaneous_advance_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: simultaneous pointer advance was not covered");
            end

            if (!frame_done_with_row_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: frame_done with row_write_done was not covered");
            end

            if (!frame_done_after_row_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: frame_done after row_write_done was not covered");
            end

            if (!frame_switch_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: frame_switch was not covered");
            end

            if (!padding_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: logical padding was not covered");
            end

            if (!last_window_two_pad_covered ||
                !last_window_one_pad_covered ||
                !last_window_zero_pad_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: not all final-window padding cases were covered");
            end

            if (!next_row_ready_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: next_row_ready assertion was not covered");
            end

            if (!write_blocked_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: write_blocked assertion was not covered");
            end


            $display("");
            $display("================================================================");
            $display("COVERAGE SUMMARY");
            $display("================================================================");
            $display(
                "Pointer / enable configurations : %0d / %0d",
                covered_configurations,
                expected_configurations
            );
            $display(
                "Logical-row routing options     : %0d",
                INIT_ROWS * NUM_BUFFERS
            );
            $display(
                "Write-buffer positions          : %0d",
                NUM_BUFFERS
            );
            $display(
                "Read-window top positions       : %0d",
                NUM_BUFFERS
            );
            $display(
                "Asynchronous reset              : covered"
            );
            $display(
                "Simultaneous pointer advance    : covered"
            );
            $display(
                "Frame-end padding               : covered"
            );
            $display(
                "Frame switch                    : covered"
            );
            $display(
                "Final-window 2/1/0 pad cases    : covered"
            );
            $display(
                "next_row_ready assertion        : covered"
            );
            $display(
                "write_blocked assertion         : covered"
            );
            $display("================================================================");

        end
    endtask


    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    initial begin

        int unsigned fill_idx;
        int unsigned top_idx;
        int unsigned combination;
        int unsigned logical_row;
        int unsigned buffer_idx;
        int unsigned step;


        //----------------------------------------------------------------------
        // Initial values
        //----------------------------------------------------------------------

        resetb         = 1'b0;

        row_write_done = 1'b0;
        advance_window = 1'b0;
        frame_done     = 1'b0;
        frame_switch   = 1'b0;

        wr_valid       = 1'b0;
        rd_valid       = 1'b0;

        error_count    = 0;
        check_count    = 0;

        reset_covered                 = 1'b0;
        simultaneous_advance_covered  = 1'b0;
        frame_done_with_row_covered    = 1'b0;
        frame_done_after_row_covered   = 1'b0;
        frame_switch_covered           = 1'b0;
        padding_covered                = 1'b0;
        last_window_two_pad_covered    = 1'b0;
        last_window_one_pad_covered    = 1'b0;
        last_window_zero_pad_covered   = 1'b0;
        next_row_ready_covered         = 1'b0;
        write_blocked_covered          = 1'b0;


        // Clear configuration coverage.
        for (fill_idx = 0;
             fill_idx < NUM_BUFFERS;
             fill_idx = fill_idx + 1) begin

            write_position_covered[fill_idx] = 1'b0;
            read_window_covered[fill_idx]    = 1'b0;

            for (top_idx = 0;
                 top_idx < NUM_BUFFERS;
                 top_idx = top_idx + 1) begin

                for (combination = 0;
                     combination < 4;
                     combination = combination + 1) begin

                    configuration_covered
                        [fill_idx]
                        [top_idx]
                        [combination] = 1'b0;

                end

            end

        end


        // Clear logical-row routing coverage.
        for (logical_row = 0;
             logical_row < INIT_ROWS;
             logical_row = logical_row + 1) begin

            for (buffer_idx = 0;
                 buffer_idx < NUM_BUFFERS;
                 buffer_idx = buffer_idx + 1) begin

                row_route_covered
                    [logical_row]
                    [buffer_idx] = 1'b0;

            end

        end


        //======================================================================
        // TEST 1
        // Asynchronous reset
        //
        // resetb is asserted between clock edges. The two internal pointers
        // must immediately return to BRAM0, which is verified through row_sel.
        // resetb is released only after sync().
        //======================================================================

        print_banner("TEST 1 - Initial asynchronous reset");

        #(CLK_PERIOD / 4);

        resetb = 1'b0;

        #1ps;

        check_state(
            0,
            0,
            1'b0,
            1'b0
        );

        check_management_state(
            0,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        reset_covered = 1'b1;

        sync();

        resetb = 1'b1;

        sync();


        //======================================================================
        // TEST 2
        // Independent pointer movement
        //
        // row_write_done advances only the fill-buffer pointer.
        // advance_window advances only the top-buffer pointer.
        //======================================================================

        print_banner("TEST 2 - Independent pointer movement");

        advance_fill_pointer();

        check_state(
            1,
            0,
            1'b0,
            1'b0
        );

        advance_top_pointer();

        check_state(
            1,
            STRIDE,
            1'b0,
            1'b0
        );


        // Return both pointers to BRAM0 using asynchronous reset before the
        // exhaustive test.
        #(CLK_PERIOD / 4);

        resetb = 1'b0;

        #1ps;

        check_state(
            0,
            0,
            1'b0,
            1'b0
        );

        sync();

        resetb = 1'b1;

        sync();


        //======================================================================
        // TEST 3
        // Exhaustive pointer and enable verification
        //
        // Every possible fill-buffer / top-buffer pair is exercised.
        //
        // For every pointer pair, all four enable combinations are tested:
        //
        //   wr_valid rd_valid
        //      0        0
        //      0        1
        //      1        0
        //      1        1
        //
        // For NUM_BUFFERS = 16:
        //
        //   16 fill positions
        // x 16 top positions
        // x 4 enable combinations
        // = 1024 complete configurations.
        //======================================================================

        print_banner("TEST 3 - Exhaustive pointer and enable combinations");

        for (step = 0;
             step < NUM_BUFFERS;
             step = step + 1) begin

            top_idx = (step * STRIDE) % NUM_BUFFERS;

            for (fill_idx = 0;
                 fill_idx < NUM_BUFFERS;
                 fill_idx = fill_idx + 1) begin

                for (combination = 0;
                     combination < 4;
                     combination = combination + 1) begin

                    drive_enable_combination(
                        fill_idx,
                        top_idx,
                        (combination >= 2),
                        ((combination % 2) == 1)
                    );

                end


                // Advance fill pointer after all four enable combinations.
                advance_fill_pointer();

            end


            // After NUM_BUFFERS fill advances, fill pointer has wrapped to
            // BRAM0. Advance top pointer to the next window position.
            advance_top_pointer();

        end


        // Both pointers have now completed a full circular rotation and must
        // be back at BRAM0.
        check_state(
            0,
            0,
            1'b0,
            1'b0
        );


        //======================================================================
        // TEST 4
        // Simultaneous pointer movement
        //
        // row_write_done and advance_window are asserted together.
        // Both pointers must advance on the same clock edge:
        // fill_buffer by one row and top_buffer by STRIDE rows.
        //
        // A complete circular rotation is performed to verify wrap-around.
        //======================================================================

        print_banner("TEST 4 - Simultaneous pointer advance and wrap-around");

        for (step = 0;
             step < NUM_BUFFERS;
             step = step + 1) begin

            advance_both_pointers();

            check_state(
                (step + 1) % NUM_BUFFERS,
                ((step + 1) * STRIDE) % NUM_BUFFERS,
                1'b0,
                1'b0
            );

        end


        //======================================================================
        // TEST 5
        // Asynchronous reset after normal activity
        //
        // Move both pointers away from BRAM0 and enable both read and write.
        // resetb is then asserted between clock edges.
        //
        // The pointer-derived outputs must immediately return to the reset
        // configuration without waiting for another rising clock edge.
        //======================================================================

        print_banner("TEST 5 - Asynchronous reset after activity");

        for (step = 0; step < 3; step = step + 1)
            advance_fill_pointer();

        for (step = 0; step < 5; step = step + 1)
            advance_top_pointer();


        drive_enable_combination(
            3,
            (5 * STRIDE) % NUM_BUFFERS,
            1'b1,
            1'b1
        );


        #(CLK_PERIOD / 4);

        resetb = 1'b0;

        #1ps;


        // wr_valid and rd_valid remain asserted. Only the internal pointers
        // are reset, therefore the enables must immediately reflect the
        // BRAM0 reset positions.
        check_state(
            0,
            0,
            1'b1,
            1'b1
        );

        check_management_state(
            0,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        sync();

        resetb = 1'b1;

        sync();


        check_state(
            0,
            0,
            1'b1,
            1'b1
        );


        // Return valid inputs to zero.
        sync();

        wr_valid = 1'b0;
        rd_valid = 1'b0;


        //======================================================================
        // TEST 6
        // Occupied-row tracking
        //
        // Verify the two occupancy thresholds:
        //   - next_row_ready is asserted only when STRIDE additional rows
        //     exist beyond the active INIT_ROWS window.
        //   - write_blocked is asserted when only PAD_ROWS free slots remain.
        //
        // Also verify simultaneous row_write_done and advance_window.
        //======================================================================

        print_banner("TEST 6 - Occupied-row tracking");

        // Reset occupancy and pointer state before the occupancy test.
        #(CLK_PERIOD / 4);

        resetb = 1'b0;

        #1ps;

        check_management_state(
            0,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        sync();

        resetb = 1'b1;

        sync();


        // INIT_ROWS completed rows are enough for the active window, but there
        // are not yet STRIDE additional rows for the next window.
        for (step = 0; step < INIT_ROWS; step = step + 1)
            advance_fill_pointer();

        check_management_state(
            INIT_ROWS,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        // STRIDE additional rows make the next processing window available.
        for (step = 0; step < STRIDE; step = step + 1)
            advance_fill_pointer();

        check_management_state(
            INIT_ROWS + STRIDE,
            1'b1,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        next_row_ready_covered = 1'b1;


        // Continue writing until only PAD_ROWS physical slots remain free.
        for (step = INIT_ROWS + STRIDE;
             step < (NUM_BUFFERS - PAD_ROWS);
             step = step + 1)
            advance_fill_pointer();

        check_management_state(
            NUM_BUFFERS - PAD_ROWS,
            1'b1,
            1'b1,
            {INIT_ROWS{1'b0}}
        );

        write_blocked_covered = 1'b1;


        // Releasing STRIDE rows clears write_blocked.
        advance_top_pointer();

        check_management_state(
            NUM_BUFFERS - PAD_ROWS - STRIDE,
            1'b1,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        // A simultaneous write adds one row while the window advance releases
        // STRIDE rows.
        advance_both_pointers();

        check_management_state(
            NUM_BUFFERS - PAD_ROWS - (2 * STRIDE) + 1,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        //======================================================================
        // TEST 7
        // End-of-frame padding and frame switch
        //
        // HPS already supplies the one-pixel image border. The FPGA therefore
        // reserves only STRIDE-1 additional logical rows at frame_done.
        // Verify final windows containing two, one, and zero logical padding
        // rows, and verify both supported frame_done timings.
        //======================================================================

        print_banner("TEST 7 - End-of-frame padding and frame switch");


        //----------------------------------------------------------------------
        // Case A: final window = RRRPP
        // frame_done together with the final row_write_done.
        //----------------------------------------------------------------------

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;
        sync();
        resetb = 1'b1;
        sync();

        for (step = 0; step < (STRIDE - 1); step = step + 1)
            advance_fill_pointer();

        sync();
        row_write_done = 1'b1;
        frame_done     = 1'b1;

        sync();
        row_write_done = 1'b0;
        frame_done     = 1'b0;
        #1ps;

        check_management_state(
            INIT_ROWS,
            1'b0,
            1'b0,
            {{PAD_ROWS{1'b1}}, {(INIT_ROWS-PAD_ROWS){1'b0}}}
        );

        check_count = check_count + 1;
        assert (last_window === 1'b1)
        else begin
            error_count = error_count + 1;
            $error("Final RRRPP window was not detected");
        end

        last_window_two_pad_covered = 1'b1;
        frame_done_with_row_covered = 1'b1;
        padding_covered             = 1'b1;

        drive_enable_combination(
            INIT_ROWS,
            0,
            1'b1,
            1'b1
        );

        sync();
        wr_valid       = 1'b0;
        rd_valid       = 1'b0;
        row_write_done = 1'b1;
        frame_switch   = 1'b1;

        sync();
        row_write_done = 1'b0;
        frame_switch   = 1'b0;
        #1ps;

        check_state(
            INIT_ROWS + 1,
            INIT_ROWS,
            1'b0,
            1'b0
        );

        check_management_state(
            1,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        frame_switch_covered = 1'b1;


        //----------------------------------------------------------------------
        // Case B: final window = RRRRP
        // frame_done is asserted after the final row has already completed.
        //----------------------------------------------------------------------

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;
        sync();
        resetb = 1'b1;
        sync();

        for (step = 0; step < (INIT_ROWS - 1); step = step + 1)
            advance_fill_pointer();

        check_management_state(
            INIT_ROWS - 1,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        sync();
        frame_done = 1'b1;

        sync();
        frame_done = 1'b0;
        #1ps;

        check_management_state(
            (INIT_ROWS - 1) + PAD_ROWS,
            1'b0,
            1'b0,
            {{1{1'b1}}, {(INIT_ROWS-1){1'b0}}}
        );

        check_count = check_count + 1;
        assert (last_window === 1'b1)
        else begin
            error_count = error_count + 1;
            $error("Final RRRRP window was not detected");
        end

        last_window_one_pad_covered = 1'b1;
        frame_done_after_row_covered = 1'b1;

        sync();
        frame_switch = 1'b1;

        sync();
        frame_switch = 1'b0;
        #1ps;

        check_state(
            (INIT_ROWS - 1) + PAD_ROWS,
            (INIT_ROWS - 1) + PAD_ROWS,
            1'b0,
            1'b0
        );

        check_management_state(
            0,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        //----------------------------------------------------------------------
        // Case C: final window = RRRRR
        // The two reserved tail-padding slots are outside the active window.
        //----------------------------------------------------------------------

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;
        sync();
        resetb = 1'b1;
        sync();

        for (step = 0; step < INIT_ROWS; step = step + 1)
            advance_fill_pointer();

        sync();
        frame_done = 1'b1;

        sync();
        frame_done = 1'b0;
        #1ps;

        check_management_state(
            INIT_ROWS + PAD_ROWS,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );

        check_count = check_count + 1;
        assert (last_window === 1'b1)
        else begin
            error_count = error_count + 1;
            $error("Final RRRRR window was not detected");
        end

        last_window_zero_pad_covered = 1'b1;

        sync();
        frame_switch = 1'b1;

        sync();
        frame_switch = 1'b0;
        #1ps;

        check_state(
            INIT_ROWS + PAD_ROWS,
            INIT_ROWS + PAD_ROWS,
            1'b0,
            1'b0
        );

        check_management_state(
            0,
            1'b0,
            1'b0,
            {INIT_ROWS{1'b0}}
        );


        //======================================================================
        // TEST 8
        // Coverage verification
        //
        // Explicitly verify that every required control configuration and every
        // logical-row / physical-BRAM mapping was exercised.
        //======================================================================

        print_banner("TEST 8 - Coverage verification");

        check_coverage();


        //======================================================================
        // Test Summary
        //======================================================================

        if (error_count == 0) begin

            $display("");
            $display("========================================");
            $display("tb_buffer_control: ALL TESTS PASSED");
            $display("Checks performed: %0d", check_count);
            $display("========================================");
            $display("");

        end
        else begin

            $fatal(
                1,
                "\ntb_buffer_control: FAILED with %0d error(s)\n",
                error_count
            );

        end


        #20;
        $stop;

    end

endmodule