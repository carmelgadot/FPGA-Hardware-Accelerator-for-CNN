`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// tb_output_buffer_mux.sv
//
// Functional testbench for 'output_buffer_mux'.
//
// The DUT is purely combinational, therefore:
//   - No clock is required.
//   - No reset is required.
//   - Inputs are driven directly.
//   - A small #1 delay is used after every input change.
//
// Purpose:
//   - Verify selection of output-buffer group 0.
//   - Verify selection of output-buffer group 1.
//   - Verify all three lanes of each group are routed correctly.
//   - Verify read_data follows buffer_data changes for a fixed group selection.
//   - Verify that all six physical-buffer to output-lane routes are covered.
//
// Methodology:
//   - Uses an independent golden model for the two expected output groups.
//   - The golden model does not reproduce the DUT indexing expression.
//   - Expected group contents are defined explicitly and compared against
//     the externally observable DUT outputs.
//
// Default organization:
//   group 0 -> BRAM0, BRAM1, BRAM2
//   group 1 -> BRAM3, BRAM4, BRAM5
// -----------------------------------------------------------------------------

module tb_output_buffer_mux;

    parameter int DATA_WIDTH         = 8;
    parameter int NUM_OUTPUT_BUFFERS = 6;
    parameter int PARALLEL_OUTPUTS   = 3;
    parameter int INITIAL_DATA_BASE  = 16;
    parameter int UPDATED_DATA_BASE  = 80;

    typedef logic [DATA_WIDTH-1:0] data_t;


    // DUT inputs
    logic [DATA_WIDTH-1:0] buffer_data [0:NUM_OUTPUT_BUFFERS-1];
    logic                  read_group_sel;

    // DUT outputs
    logic [DATA_WIDTH-1:0] read_data [0:PARALLEL_OUTPUTS-1];


    // Independent golden model
    logic [DATA_WIDTH-1:0] golden_group0      [0:PARALLEL_OUTPUTS-1];
    logic [DATA_WIDTH-1:0] golden_group1      [0:PARALLEL_OUTPUTS-1];
    logic [DATA_WIDTH-1:0] expected_read_data [0:PARALLEL_OUTPUTS-1];


    // Coverage tracking
    bit group_covered [0:1];
    bit route_covered [0:NUM_OUTPUT_BUFFERS-1];

    integer errors;


    // Device Under Test
    output_buffer_mux #(
        .DATA_WIDTH         (DATA_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) dut (
        .buffer_data    (buffer_data),
        .read_group_sel (read_group_sel),
        .read_data      (read_data)
    );


    // -------------------------------------------------------------------------
    // Load the initial deterministic DUT stimulus and the independent expected
    // group contents. The expected routing is written explicitly rather than
    // calculated with the DUT's group-indexing expression.
    // -------------------------------------------------------------------------
    task automatic load_initial_pattern;
        begin
            buffer_data[0] = data_t'(INITIAL_DATA_BASE + 0);
            buffer_data[1] = data_t'(INITIAL_DATA_BASE + 1);
            buffer_data[2] = data_t'(INITIAL_DATA_BASE + 2);
            buffer_data[3] = data_t'(INITIAL_DATA_BASE + 3);
            buffer_data[4] = data_t'(INITIAL_DATA_BASE + 4);
            buffer_data[5] = data_t'(INITIAL_DATA_BASE + 5);

            golden_group0[0] = data_t'(INITIAL_DATA_BASE + 0);
            golden_group0[1] = data_t'(INITIAL_DATA_BASE + 1);
            golden_group0[2] = data_t'(INITIAL_DATA_BASE + 2);

            golden_group1[0] = data_t'(INITIAL_DATA_BASE + 3);
            golden_group1[1] = data_t'(INITIAL_DATA_BASE + 4);
            golden_group1[2] = data_t'(INITIAL_DATA_BASE + 5);
        end
    endtask


    // -------------------------------------------------------------------------
    // Load a second deterministic pattern while preserving the same explicitly
    // defined physical-buffer to output-group relationship.
    // -------------------------------------------------------------------------
    task automatic load_updated_pattern;
        begin
            buffer_data[0] = data_t'(UPDATED_DATA_BASE + 0);
            buffer_data[1] = data_t'(UPDATED_DATA_BASE + 1);
            buffer_data[2] = data_t'(UPDATED_DATA_BASE + 2);
            buffer_data[3] = data_t'(UPDATED_DATA_BASE + 20 + 3);
            buffer_data[4] = data_t'(UPDATED_DATA_BASE + 20 + 4);
            buffer_data[5] = data_t'(UPDATED_DATA_BASE + 20 + 5);

            golden_group0[0] = data_t'(UPDATED_DATA_BASE + 0);
            golden_group0[1] = data_t'(UPDATED_DATA_BASE + 1);
            golden_group0[2] = data_t'(UPDATED_DATA_BASE + 2);

            golden_group1[0] = data_t'(UPDATED_DATA_BASE + 20 + 3);
            golden_group1[1] = data_t'(UPDATED_DATA_BASE + 20 + 4);
            golden_group1[2] = data_t'(UPDATED_DATA_BASE + 20 + 5);
        end
    endtask


    // -------------------------------------------------------------------------
    // Check the complete selected output group against the independent golden
    // model. No physical-buffer index is calculated here.
    // -------------------------------------------------------------------------
    task automatic check_selected_group(
        input logic group_sel
    );
        int lane_idx;

        begin
            if (~group_sel) begin
                expected_read_data[0] = golden_group0[0];
                expected_read_data[1] = golden_group0[1];
                expected_read_data[2] = golden_group0[2];
            end
            else begin
                expected_read_data[0] = golden_group1[0];
                expected_read_data[1] = golden_group1[1];
                expected_read_data[2] = golden_group1[2];
            end

            for (lane_idx = 0;
                 lane_idx < PARALLEL_OUTPUTS;
                 lane_idx = lane_idx + 1) begin

                if (read_data[lane_idx] !== expected_read_data[lane_idx]) begin
                    $error(
                        "group=%0d lane=%0d: expected=%0d got=%0d",
                        group_sel,
                        lane_idx,
                        expected_read_data[lane_idx],
                        read_data[lane_idx]
                    );
                    errors = errors + 1;
                end
            end

            if (~group_sel) begin
                route_covered[0] = 1'b1;
                route_covered[1] = 1'b1;
                route_covered[2] = 1'b1;
            end
            else begin
                route_covered[3] = 1'b1;
                route_covered[4] = 1'b1;
                route_covered[5] = 1'b1;
            end

            group_covered[group_sel] = 1'b1;
        end
    endtask


    initial begin
        int buffer_idx;

        errors         = 0;
        read_group_sel = 1'b0;

        for (buffer_idx = 0;
             buffer_idx < NUM_OUTPUT_BUFFERS;
             buffer_idx = buffer_idx + 1)
            route_covered[buffer_idx] = 1'b0;

        group_covered[0] = 1'b0;
        group_covered[1] = 1'b0;

        for (buffer_idx = 0;
             buffer_idx < PARALLEL_OUTPUTS;
             buffer_idx = buffer_idx + 1)
            expected_read_data[buffer_idx] = data_t'(0);

        load_initial_pattern();
        #1;


        // ---------------------------------------------------------------------
        // TEST 1: Select group 0.
        // ---------------------------------------------------------------------
        $display("TEST 1 - Select output-buffer group 0");
        read_group_sel = 1'b0;
        #1;
        check_selected_group(1'b0);


        // ---------------------------------------------------------------------
        // TEST 2: Select group 1.
        // ---------------------------------------------------------------------
        $display("TEST 2 - Select output-buffer group 1");
        read_group_sel = 1'b1;
        #1;
        check_selected_group(1'b1);


        // ---------------------------------------------------------------------
        // TEST 3: Data-change behavior while group 0 remains selected.
        // ---------------------------------------------------------------------
        $display("TEST 3 - Data change with group 0 selected");
        read_group_sel = 1'b0;
        load_updated_pattern();
        #1;
        check_selected_group(1'b0);


        // ---------------------------------------------------------------------
        // TEST 4: Data-change behavior while group 1 remains selected.
        // ---------------------------------------------------------------------
        $display("TEST 4 - Data change with group 1 selected");
        read_group_sel = 1'b1;
        #1;
        check_selected_group(1'b1);


        // ---------------------------------------------------------------------
        // Coverage checks.
        // ---------------------------------------------------------------------
        if (!group_covered[0]) begin
            $error("Coverage FAILED: group 0 was never selected");
            errors = errors + 1;
        end

        if (!group_covered[1]) begin
            $error("Coverage FAILED: group 1 was never selected");
            errors = errors + 1;
        end

        for (buffer_idx = 0;
             buffer_idx < NUM_OUTPUT_BUFFERS;
             buffer_idx = buffer_idx + 1) begin

            if (!route_covered[buffer_idx]) begin
                $error("Coverage FAILED: BRAM%0d route was never checked", buffer_idx);
                errors = errors + 1;
            end
        end


        // ---------------------------------------------------------------------
        // Final test result.
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("--------------------------------------------------");
            $display("tb_output_buffer_mux PASSED");
            $display("Both output groups and all %0d routes were checked.",
                     NUM_OUTPUT_BUFFERS);
            $display("--------------------------------------------------");
        end
        else begin
            $error("tb_output_buffer_mux FAILED with %0d errors", errors);
        end

        #5;
        $stop;
    end

endmodule
