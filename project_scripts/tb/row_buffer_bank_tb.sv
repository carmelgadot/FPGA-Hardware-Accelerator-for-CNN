`timescale 1ns/1ps

//==============================================================================
/*
  Module Name : row_buffer_bank_tb.sv

  Description :
    Integration testbench for row_buffer_bank.

    The testbench verifies the complete wrapper-level data path between the
    physical BRAM row buffers and the logical processing-window outputs.

        write inputs -> input_buffers -> buffer_data -> row_buffer_mux
                     -> pixel_out

   The internal modules are assumed to be verified independently, therefore
    this testbench does not attempt exhaustive functional coverage.

  General Goals  :
    - Verify end-to-end integration of input_buffers and row_buffer_mux
    - Verify simultaneous read of all five logical rows from five physical BRAMs
    - Verify continuous cycle-by-cycle reads from consecutive addresses
    - Verify simultaneous row writing while five active rows are being read
    - Verify correct circular-buffer remapping after advancing the window
    - Verify that the shifted window immediately uses the newly written row
    - Validate asynchronous reset behavior before and after normal activity
    - Verify that reset clears BRAM outputs without erasing stored memory data

  Methodology   :
    - Uses sync() to align stimulus to posedges, except when demonstrating async-assert resetb
    - Uses deterministic address-dependent data patterns for automatic checking
    - Uses assertions for automatic pass/fail detection
    - Drives consecutive read/write addresses every clock cycle to model the
      intended processing pipeline
    - Accounts for the two-clock registered BRAM read latency
*/
//==============================================================================

module row_buffer_bank_tb;

    //--------------------------------------------------------------------------
    // Testbench parameters
    //--------------------------------------------------------------------------

    localparam int unsigned DATA_WIDTH      = 8;
    localparam int unsigned ADDR_WIDTH      = 10;
    localparam int unsigned NUM_BUFFERS     = 16;
    localparam int unsigned INIT_ROWS       = 5;
    localparam int unsigned PIPELINE_LENGTH = 16;

    typedef logic [ADDR_WIDTH-1:0]  addr_t;
    typedef logic [DATA_WIDTH-1:0]  data_t;
    typedef logic [NUM_BUFFERS-1:0] mask_t;

    localparam time CLK_PERIOD = 10ns;

    localparam logic [ADDR_WIDTH-1:0] RESET_TEST_ADDR  = 10'd100;
    localparam logic [DATA_WIDTH-1:0] RESET_TEST_VALUE = 8'd201;


    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------

    logic                          clk;
    logic                          resetb;

    logic [ADDR_WIDTH-1:0]         rd_addr;
    logic [ADDR_WIDTH-1:0]         wr_addr;
    logic [DATA_WIDTH-1:0]         data;

    logic [NUM_BUFFERS-1:0]        wren;
    logic [NUM_BUFFERS-1:0]        rden;

    logic [NUM_BUFFERS-1:0]        row_sel   [0:INIT_ROWS-1];
    logic [INIT_ROWS-1:0]          row_padding;
    logic [DATA_WIDTH-1:0]         pixel_out [0:INIT_ROWS-1];

    int unsigned errors;
    int unsigned row_idx;


    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------

    row_buffer_bank #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS)
    ) dut (
        .clk       (clk),
        .resetb    (resetb),
        .rd_addr   (rd_addr),
        .wr_addr   (wr_addr),
        .data      (data),
        .wren      (wren),
        .rden        (rden),
        .row_sel     (row_sel),
        .row_padding (row_padding),
        .pixel_out   (pixel_out)
    );


    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end


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
    // Deterministic data pattern
    //
    // Every physical buffer receives a different data range, while consecutive
    // addresses also contain different values. This allows the testbench to
    // detect both incorrect BRAM selection and incorrect address sequencing.
    //--------------------------------------------------------------------------

    function automatic logic [DATA_WIDTH-1:0] pattern_value(
        input int unsigned buffer_idx,
        input int unsigned address
    );
        int unsigned value;

        begin
            value = 10 + (buffer_idx * 20) + address;
            pattern_value = value[DATA_WIDTH-1:0];
        end
    endfunction


    //--------------------------------------------------------------------------
    // Configure the five logical rows of the active processing window.
    //
    // This task only changes combinational row_sel values and must therefore
    // be called immediately after sync().
    //--------------------------------------------------------------------------

    task automatic configure_window(
        input int unsigned buffer0,
        input int unsigned buffer1,
        input int unsigned buffer2,
        input int unsigned buffer3,
        input int unsigned buffer4
    );
        int unsigned logical_row;

        begin
            for (logical_row = 0;
                 logical_row < INIT_ROWS;
                 logical_row = logical_row + 1)
                row_sel[logical_row] = mask_t'(0);

            row_sel[0][buffer0] = 1'b1;
            row_sel[1][buffer1] = 1'b1;
            row_sel[2][buffer2] = 1'b1;
            row_sel[3][buffer3] = 1'b1;
            row_sel[4][buffer4] = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Write one word into one physical BRAM.
    //--------------------------------------------------------------------------

    task automatic write_word(
        input int unsigned                   buffer_idx,
        input logic [ADDR_WIDTH-1:0]         address,
        input logic [DATA_WIDTH-1:0]         value
    );
        begin
            sync();

            wr_addr = address;
            data    = value;
            wren    = mask_t'(0);
            rden    = mask_t'(0);

            wren[buffer_idx] = 1'b1;

            sync();

            wren = mask_t'(0);
        end
    endtask


    //--------------------------------------------------------------------------
    // Write one complete test row into one physical BRAM.
    //
    // Consecutive addresses are written on consecutive clock cycles.
    //--------------------------------------------------------------------------

    task automatic write_row(
        input int unsigned buffer_idx
    );
        int unsigned address_idx;

        begin
            sync();

            wren = mask_t'(0);
            rden = mask_t'(0);
            wren[buffer_idx] = 1'b1;

            for (address_idx = 0;
                 address_idx < PIPELINE_LENGTH;
                 address_idx = address_idx + 1) begin

                wr_addr = address_idx[ADDR_WIDTH-1:0];
                data    = pattern_value(buffer_idx, address_idx);

                sync();
            end

            wren = mask_t'(0);
        end
    endtask


    //--------------------------------------------------------------------------
    // Check one logical-row output.
    //--------------------------------------------------------------------------

    task automatic check_pixel(
        input int unsigned                   logical_row,
        input logic [DATA_WIDTH-1:0]         expected
    );
        begin
            assert (pixel_out[logical_row] === expected)
            else begin
                $error(
                    "logical row %0d: expected %0d, got %0d",
                    logical_row,
                    expected,
                    pixel_out[logical_row]
                );
                errors = errors + 1;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Check all five logical-row outputs against explicit expected values.
    //--------------------------------------------------------------------------

    task automatic check_window_values(
        input logic [DATA_WIDTH-1:0] expected0,
        input logic [DATA_WIDTH-1:0] expected1,
        input logic [DATA_WIDTH-1:0] expected2,
        input logic [DATA_WIDTH-1:0] expected3,
        input logic [DATA_WIDTH-1:0] expected4
    );
        begin
            check_pixel(0, expected0);
            check_pixel(1, expected1);
            check_pixel(2, expected2);
            check_pixel(3, expected3);
            check_pixel(4, expected4);
        end
    endtask


    //--------------------------------------------------------------------------
    // Check one complete logical window for a specific read address.
    //--------------------------------------------------------------------------

    task automatic check_window_address(
        input int unsigned buffer0,
        input int unsigned buffer1,
        input int unsigned buffer2,
        input int unsigned buffer3,
        input int unsigned buffer4,
        input int unsigned address
    );
        begin
            check_pixel(0, pattern_value(buffer0, address));
            check_pixel(1, pattern_value(buffer1, address));
            check_pixel(2, pattern_value(buffer2, address));
            check_pixel(3, pattern_value(buffer3, address));
            check_pixel(4, pattern_value(buffer4, address));
        end
    endtask


    //--------------------------------------------------------------------------
    // Run one continuous pipeline sequence.
    //
    // Five physical BRAMs are read in parallel while a sixth physical BRAM is
    // written on every clock cycle. rd_addr and wr_addr both advance by one
    // address every cycle with no gaps inside the sequence.
    //--------------------------------------------------------------------------

    task automatic run_pipeline(
        input int unsigned write_buffer,
        input int unsigned buffer0,
        input int unsigned buffer1,
        input int unsigned buffer2,
        input int unsigned buffer3,
        input int unsigned buffer4
    );
        int unsigned cycle_idx;

        begin
            sync();

            wren = mask_t'(0);
            rden = mask_t'(0);

            wren[write_buffer] = 1'b1;

            rden[buffer0] = 1'b1;
            rden[buffer1] = 1'b1;
            rden[buffer2] = 1'b1;
            rden[buffer3] = 1'b1;
            rden[buffer4] = 1'b1;

            configure_window(
                buffer0,
                buffer1,
                buffer2,
                buffer3,
                buffer4
            );

            for (cycle_idx = 0;
                 cycle_idx < PIPELINE_LENGTH;
                 cycle_idx = cycle_idx + 1) begin

                rd_addr = cycle_idx[ADDR_WIDTH-1:0];
                wr_addr = cycle_idx[ADDR_WIDTH-1:0];
                data    = pattern_value(write_buffer, cycle_idx);

                sync();

                if (cycle_idx > 0)
                    check_window_address(
                        buffer0,
                        buffer1,
                        buffer2,
                        buffer3,
                        buffer4,
                        cycle_idx - 1
                    );
            end

            wren = mask_t'(0);

            sync();

            check_window_address(
                buffer0,
                buffer1,
                buffer2,
                buffer3,
                buffer4,
                PIPELINE_LENGTH - 1
            );

            rden = mask_t'(0);
        end
    endtask


    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------

    initial begin

        //----------------------------------------------------------------------
        // Initial values
        //----------------------------------------------------------------------

        resetb  = 1'b1;
        rd_addr = addr_t'(0);
        wr_addr = addr_t'(0);
        data    = data_t'(0);
        wren        = mask_t'(0);
        rden        = mask_t'(0);
        row_padding = {INIT_ROWS{1'b0}};
        errors      = 0;

        for (row_idx = 0;
             row_idx < INIT_ROWS;
             row_idx = row_idx + 1)
            row_sel[row_idx] = mask_t'(0);


        // ---------------------------------------------------------------------
        // TEST 1A
        // Test procedure:
        //   - Selects valid physical BRAM outputs for all logical rows.
        //   - Asserts resetb low between clock edges.
        //   - Checks that all selected pixel_out values clear immediately.
        //   - Releases resetb only after sync().
        // ---------------------------------------------------------------------

        $display("\nTEST 1A - Initial asynchronous reset");

        configure_window(0, 1, 2, 3, 4);

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;

        check_window_values(8'd0, 8'd0, 8'd0, 8'd0, 8'd0);

        sync();
        resetb = 1'b1;

        sync();


        // ---------------------------------------------------------------------
        // TEST 1B
        // Test procedure:
        //   - Writes a known value into one physical BRAM and reads it back.
        //   - Asserts resetb asynchronously after valid output data is present.
        //   - Checks that pixel_out clears immediately.
        //   - Releases resetb and reads the same address again.
        //   - Verifies that reset cleared the output but did not erase memory.
        // ---------------------------------------------------------------------

        $display("TEST 1B - Asynchronous reset after activity");

        write_word(0, RESET_TEST_ADDR, RESET_TEST_VALUE);

        sync();

        wren    = mask_t'(0);
        rden    = mask_t'(0);
        rd_addr = RESET_TEST_ADDR;

        rden[0] = 1'b1;

        configure_window(0, 1, 2, 3, 4);

        sync();
        sync();

        check_pixel(0, RESET_TEST_VALUE);

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;

        check_window_values(8'd0, 8'd0, 8'd0, 8'd0, 8'd0);

        sync();
        resetb = 1'b1;

        sync();
        sync();

        check_pixel(0, RESET_TEST_VALUE);

        sync();
        rden = mask_t'(0);


        // ---------------------------------------------------------------------
        // TEST 2
        // Test procedure:
        //   - Preloads buffers 6, 7, 0, 1 and 2 with address-dependent data.
        //   - Maps these buffers to the five logical rows of the active window.
        //   - Reads all five rows in parallel from consecutive addresses.
        //   - Simultaneously writes the next row into buffer 3.
        //   - Advances rd_addr and wr_addr every clock cycle with no gaps.
        //   - Checks one complete five-pixel output vector every clock after
        //     the BRAM read pipeline becomes valid.
        // ---------------------------------------------------------------------

        $display("TEST 2 - Continuous five-row read with simultaneous row write");

        write_row(6);
        write_row(7);
        write_row(0);
        write_row(1);
        write_row(2);

        run_pipeline(
            3,
            6, 7, 0, 1, 2
        );


        // ---------------------------------------------------------------------
        // TEST 3
        // Test procedure:
        //   - Advances the logical window from {6,7,0,1,2} to {7,0,1,2,3}.
        //   - Uses buffer 3, written during TEST 2, as the new fifth row.
        //   - Reads the shifted five-row window continuously, one address per
        //     clock cycle.
        //   - Simultaneously writes the following row into buffer 4.
        //   - Checks the complete shifted window every valid pipeline cycle.
        // ---------------------------------------------------------------------

        $display("TEST 3 - Window shift followed by another pipeline sequence");

        run_pipeline(
            4,
            7, 0, 1, 2, 3
        );


        // ---------------------------------------------------------------------
        // TEST 4
        // Test procedure:
        //   - Uses a valid five-row window and enables padding on rows 1..4.
        //   - Reads all five selected physical BRAMs exactly as before.
        //   - Verifies that the mux passes the real first row and forces the
        //     four padded logical rows to zero.
        // ---------------------------------------------------------------------

        $display("TEST 4 - Padding rows forced to zero");

        sync();

        wren        = mask_t'(0);
        rden        = mask_t'(0);
        rd_addr     = addr_t'(3);
        row_padding = 5'b11110;

        rden[7] = 1'b1;
        rden[0] = 1'b1;
        rden[1] = 1'b1;
        rden[2] = 1'b1;
        rden[3] = 1'b1;

        configure_window(7, 0, 1, 2, 3);

        sync();
        sync();

        check_window_values(
            pattern_value(7, 3),
            8'd0,
            8'd0,
            8'd0,
            8'd0
        );

        sync();

        rden        = mask_t'(0);
        row_padding = {INIT_ROWS{1'b0}};


        //--------------------------------------------------------------------------
        // Test summary
        //--------------------------------------------------------------------------

        if (errors == 0) begin
            $display("\n========================================");
            $display("row_buffer_bank_tb: ALL TESTS PASSED");
            $display("========================================\n");
        end
        else begin
            $fatal(
                1,
                "\nrow_buffer_bank_tb: FAILED with %0d error(s)\n",
                errors
            );
        end

        

        #20;
        $stop;

    end

endmodule
