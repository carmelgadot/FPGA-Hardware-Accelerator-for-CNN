`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// tb_row_buffer_mux.sv
//
// Functional testbench for 'row_buffer_mux'.
//
// The DUT is purely combinational, therefore:
//   - No clock is required.
//   - No reset is required.
//   - Inputs are driven directly.
//   - A small #1 delay is used after every input change.
//
// Purpose:
//   - Verify that every logical row receives the data from the physical BRAM
//     selected by its one-hot row_sel value.
//   - Test every valid combination of physical-BRAM selections.
//   - Verify that every logical-row / physical-BRAM routing option was covered.
//   - Verify that every invalid binary row_sel value activates the default case
//     and produces zero on the corresponding pixel_out.
//   - Verify that pixel_out follows changes in buffer_data for a fixed valid selection.
//
// For the default configuration:
//   INIT_ROWS   = 5
//   NUM_BUFFERS = 8
//
// Each logical row can independently select one of 8 BRAMs.
// Therefore the complete valid input space contains:
//
//   8^5 = 32768 combinations.
//
// Example:
//   row_sel[0] = 00000100 -> pixel_out[0] must equal buffer_data[2]
//   row_sel[1] = 10000000 -> pixel_out[1] must equal buffer_data[7]
//   row_sel[2] = 00000001 -> pixel_out[2] must equal buffer_data[0]
//   ...
//
// Method:
//   - Give every BRAM output a unique data value.
//   - Sweep through all valid row_sel combinations.
//   - Compare every pixel_out against the selected BRAM data.
//   - Track functional coverage for every row-to-BRAM routing option.
//   - Sweep all invalid binary row_sel values for every logical row.
//   - Change the BRAM data values while keeping valid row selections fixed,
//     and verify that the corresponding pixel_out values update correctly.
// -----------------------------------------------------------------------------

module tb_row_buffer_mux;

    parameter int DATA_WIDTH  = 8;
    parameter int NUM_BUFFERS = 8;
    parameter int INIT_ROWS   = 5;
    parameter int INITIAL_DATA_BASE = 16;
    parameter int UPDATED_DATA_BASE = 5;

    typedef logic [DATA_WIDTH-1:0] data_t;

    localparam int TOTAL_COMBINATIONS       = NUM_BUFFERS ** INIT_ROWS;
    localparam int TOTAL_SELECTOR_VALUES     = 2 ** NUM_BUFFERS;
    localparam int INVALID_SELECTORS_PER_ROW = TOTAL_SELECTOR_VALUES - NUM_BUFFERS;
    localparam int TOTAL_INVALID_TESTS       = INIT_ROWS * INVALID_SELECTORS_PER_ROW;


    // DUT inputs
    logic [DATA_WIDTH-1:0]  buffer_data [0:NUM_BUFFERS-1];
    logic [NUM_BUFFERS-1:0] row_sel     [0:INIT_ROWS-1];
    logic [INIT_ROWS-1:0]   row_padding;

    // DUT outputs
    logic [DATA_WIDTH-1:0]  pixel_out   [0:INIT_ROWS-1];


    // Coverage tracking:
    // route_covered[row][buffer] = 1 when that logical row has been tested
    // using that physical BRAM.
    bit route_covered [0:INIT_ROWS-1][0:NUM_BUFFERS-1];

    integer combinations_tested;
    integer invalid_tests_tested;
    integer errors;


    // Device Under Test
    row_buffer_mux #(
        .DATA_WIDTH  (DATA_WIDTH),
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS)
    ) dut (
        .buffer_data (buffer_data),
        .row_sel     (row_sel),
        .row_padding (row_padding),
        .pixel_out   (pixel_out)
    );


    // -------------------------------------------------------------------------
    // Helper: generate a one-hot selector for a physical BRAM index.
    // -------------------------------------------------------------------------
    function automatic logic [NUM_BUFFERS-1:0] onehot(
        input integer buffer_index
    );
        onehot = {{(NUM_BUFFERS-1){1'b0}}, 1'b1} << buffer_index;
    endfunction


    // -------------------------------------------------------------------------
    // Helper: check all logical-row outputs for the current selection.
    //
    // selected_buffer[row] contains the physical BRAM index expected to supply
    // that logical row.
    // -------------------------------------------------------------------------
    task automatic check_outputs(
        input integer selected_buffer [0:INIT_ROWS-1],
        input integer combination_number
    );

        for (int row = 0; row < INIT_ROWS; row++) begin

            if (pixel_out[row] !== buffer_data[selected_buffer[row]]) begin

                $error(
                    "Combination %0d, logical row %0d: selected BRAM%0d, expected=%0d got=%0d",
                    combination_number,
                    row,
                    selected_buffer[row],
                    buffer_data[selected_buffer[row]],
                    pixel_out[row]
                );

                errors = errors + 1;

            end

            // Mark this logical-row -> physical-BRAM route as covered.
            route_covered[row][selected_buffer[row]] = 1'b1;

        end

    endtask


    initial begin

        integer temp;
        integer selected_buffer [0:INIT_ROWS-1];


        combinations_tested = 0;
        invalid_tests_tested = 0;
        errors               = 0;
        row_padding          = {INIT_ROWS{1'b0}};


        // ---------------------------------------------------------------------
        // A) Initialize every BRAM output with a unique value.
        //
        // Unique values make it possible to identify exactly which physical
        // BRAM was forwarded through each mux.
        //
        // Example:
        //   BRAM0 -> 8'd16
        //   BRAM1 -> 8'd17
        //   ...
        //   BRAM7 -> 8'd23
        // ---------------------------------------------------------------------

        for (int buffer_idx = 0;
             buffer_idx < NUM_BUFFERS;
             buffer_idx++) begin

            buffer_data[buffer_idx] = data_t'(INITIAL_DATA_BASE + buffer_idx);

        end


        // Clear all selectors before starting the sweep.
        for (int row = 0; row < INIT_ROWS; row++)
            row_sel[row] = {NUM_BUFFERS{1'b0}};


        // Clear functional coverage tracking.
        for (int row = 0; row < INIT_ROWS; row++) begin
            for (int buffer_idx = 0;
                 buffer_idx < NUM_BUFFERS;
                 buffer_idx++) begin

                route_covered[row][buffer_idx] = 1'b0;

            end
        end


        #1;


        // ---------------------------------------------------------------------
        // B) Exhaustive valid-selection test.
        //
        // Each logical row can select any one of NUM_BUFFERS physical BRAMs.
        //
        // The combination number is interpreted as a base-NUM_BUFFERS number.
        // Each digit determines the BRAM selected for one logical row.
        //
        // For NUM_BUFFERS=8 and INIT_ROWS=5 this tests all 32768 possible
        // combinations.
        // ---------------------------------------------------------------------

        for (int combination = 0;
             combination < TOTAL_COMBINATIONS;
             combination++) begin

            temp = combination;

            // Decode the current combination into one BRAM selection per row.
            for (int row = 0; row < INIT_ROWS; row++) begin

                selected_buffer[row] = temp % NUM_BUFFERS;
                temp = temp / NUM_BUFFERS;

                row_sel[row] = onehot(selected_buffer[row]);

            end


            #1; // Allow combinational logic to settle


            check_outputs(selected_buffer, combination);

            combinations_tested = combinations_tested + 1;

        end


        // ---------------------------------------------------------------------
        // C) Verify exhaustive-combination coverage.
        //
        // Make sure the test actually executed the entire valid combination
        // space.
        // ---------------------------------------------------------------------

        if (combinations_tested != TOTAL_COMBINATIONS) begin

            $error(
                "Combination coverage FAILED: expected %0d combinations, tested %0d",
                TOTAL_COMBINATIONS,
                combinations_tested
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "Combination coverage PASSED: all %0d valid combinations tested",
                TOTAL_COMBINATIONS
            );

        end


        // ---------------------------------------------------------------------
        // D) Verify row-to-BRAM routing coverage.
        //
        // Every logical row must have selected every physical BRAM at least
        // once during the exhaustive sweep.
        //
        // Default configuration:
        //   5 logical rows x 8 BRAMs = 40 routing options.
        // ---------------------------------------------------------------------

        for (int row = 0; row < INIT_ROWS; row++) begin

            for (int buffer_idx = 0;
                 buffer_idx < NUM_BUFFERS;
                 buffer_idx++) begin

                if (!route_covered[row][buffer_idx]) begin

                    $error(
                        "Coverage FAILED: logical row %0d never selected BRAM%0d",
                        row,
                        buffer_idx
                    );

                    errors = errors + 1;

                end

            end

        end


        // ---------------------------------------------------------------------
        // E) Invalid-selector / default-case test.
        //
        // The DUT case statement accepts only valid one-hot row_sel values.
        // Every other binary selector value must enter the default case and
        // drive the corresponding pixel_out to zero.
        //
        // For NUM_BUFFERS=8 there are 256 possible selector values, of which
        // 8 are valid one-hot values. Therefore, each logical row has 248
        // invalid binary selector values.
        // ---------------------------------------------------------------------

        // Start from a known valid selection for every logical row.
        for (int row = 0; row < INIT_ROWS; row++)
            row_sel[row] = onehot(0);

        #1;


        for (int test_row = 0; test_row < INIT_ROWS; test_row++) begin

            for (int selector_value = 0;
                 selector_value < TOTAL_SELECTOR_VALUES;
                 selector_value++) begin

                // Skip the valid one-hot selectors already tested above.
                if (!$onehot(selector_value[NUM_BUFFERS-1:0])) begin

                    row_sel[test_row] = selector_value[NUM_BUFFERS-1:0];

                    #1; // Allow combinational logic to settle


                    if (pixel_out[test_row] !== {DATA_WIDTH{1'b0}}) begin

                        $error(
                            "Invalid selector test, logical row %0d: row_sel=%b, expected=0 got=%0d",
                            test_row,
                            row_sel[test_row],
                            pixel_out[test_row]
                        );

                        errors = errors + 1;

                    end

                    invalid_tests_tested = invalid_tests_tested + 1;

                end

            end

            // Restore this row to a valid selector before testing the next row.
            row_sel[test_row] = onehot(0);

            #1;

        end


        // Verify that every invalid binary selector value was tested for every
        // logical row.
        if (invalid_tests_tested != TOTAL_INVALID_TESTS) begin

            $error(
                "Invalid-selector coverage FAILED: expected %0d tests, executed %0d",
                TOTAL_INVALID_TESTS,
                invalid_tests_tested
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "Invalid-selector coverage PASSED: all %0d invalid selector tests executed",
                TOTAL_INVALID_TESTS
            );

        end


        // ---------------------------------------------------------------------
        // F) Data-change test.
        //
        // Keep a fixed valid BRAM selection for each logical row, then change
        // the BRAM output data and verify that pixel_out follows the new data.
        // ---------------------------------------------------------------------

        for (int row = 0; row < INIT_ROWS; row++) begin

            selected_buffer[row] = row % NUM_BUFFERS;
            row_sel[row] = onehot(selected_buffer[row]);

        end


        #1; // Allow combinational logic to settle


        // Verify the current data before changing it.
        check_outputs(selected_buffer, TOTAL_COMBINATIONS);


        // Change every BRAM output while keeping row_sel unchanged.
        for (int buffer_idx = 0;
             buffer_idx < NUM_BUFFERS;
             buffer_idx++) begin

            buffer_data[buffer_idx] = data_t'(UPDATED_DATA_BASE + buffer_idx);

        end


        #1; // Allow combinational logic to settle


        // Verify that each output now reflects the new selected BRAM data.
        check_outputs(selected_buffer, TOTAL_COMBINATIONS);


        // ---------------------------------------------------------------------
        // G) Padding test.
        //
        // Keep valid row selections and sweep every row_padding combination.
        // A padded logical row must output zero; every non-padded row must
        // continue to forward the selected BRAM data.
        // ---------------------------------------------------------------------

        for (int padding_value = 0;
             padding_value < (1 << INIT_ROWS);
             padding_value++) begin

            row_padding = padding_value[INIT_ROWS-1:0];

            #1; // Allow combinational logic to settle

            for (int row = 0; row < INIT_ROWS; row++) begin

                if (row_padding[row]) begin

                    if (pixel_out[row] !== {DATA_WIDTH{1'b0}}) begin

                        $error(
                            "Padding test, row_padding=%b, logical row %0d: expected=0 got=%0d",
                            row_padding,
                            row,
                            pixel_out[row]
                        );

                        errors = errors + 1;

                    end

                end
                else begin

                    if (pixel_out[row] !== buffer_data[selected_buffer[row]]) begin

                        $error(
                            "Padding test, row_padding=%b, logical row %0d: expected=%0d got=%0d",
                            row_padding,
                            row,
                            buffer_data[selected_buffer[row]],
                            pixel_out[row]
                        );

                        errors = errors + 1;

                    end

                end

            end

        end

        row_padding = {INIT_ROWS{1'b0}};

        #1;


        // ---------------------------------------------------------------------
        // H) Final test result.
        // ---------------------------------------------------------------------

        if (errors == 0) begin

            $display("--------------------------------------------------");
            $display("tb_row_buffer_mux PASSED");
            $display("All %0d combinations were checked.", TOTAL_COMBINATIONS);
            $display("All %0d row-to-BRAM routes were covered.",
                     INIT_ROWS * NUM_BUFFERS);
            $display("All %0d invalid selector cases were checked.",
                     TOTAL_INVALID_TESTS);
            $display("--------------------------------------------------");

        end
        else begin

            $error("tb_row_buffer_mux FAILED with %0d errors", errors);

        end


        #5;
        $stop;

    end

endmodule