`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : output_buffer_bank_tb.sv

  Description :
    Integration testbench for output_buffer_bank.

    The testbench verifies the complete wrapper-level data path:

        three parallel inputs -> output_buffers -> buffer_data
                              -> output_buffer_mux -> read_data

    The internal modules are verified independently, therefore this testbench
    focuses on end-to-end integration rather than exhaustive submodule testing.

  General Goals :
    - Verify group 0 write/read through the complete bank.
    - Verify group 1 write/read through the complete bank.
    - Verify output_buffer_mux selects the correct physical group.
    - Verify simultaneous write of one group while the other group is read.
    - Verify ping-pong operation in both directions.
    - Verify consecutive read addresses produce consecutive output triples.
    - Verify asynchronous reset clears output registers without erasing memory.

  Methodology :
    - Uses sync() before every normal stimulus change.
    - resetb assertion is intentionally asynchronous when reset is tested.
    - Uses an independent behavioral reference memory as the golden model.
    - The golden model is updated from externally applied write transactions and
      expected read_data values are derived from that model, not from DUT state.
    - Accounts for the registered BRAM read latency.
*/
//==============================================================================

module output_buffer_bank_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------

    localparam int unsigned DATA_WIDTH         = 8;
    localparam int unsigned ADDR_WIDTH         = 10;
    localparam int unsigned NUM_OUTPUT_BUFFERS = 6;
    localparam int unsigned PARALLEL_OUTPUTS   = 3;
    localparam int unsigned DEPTH              = (1 << ADDR_WIDTH);

    localparam time CLK_PERIOD = 10ns;

    typedef logic [ADDR_WIDTH-1:0]         addr_t;
    typedef logic [DATA_WIDTH-1:0]         data_t;
    typedef logic [NUM_OUTPUT_BUFFERS-1:0] mask_t;


    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------

    logic clk;
    logic resetb;

    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [ADDR_WIDTH-1:0] wr_addr;

    logic [DATA_WIDTH-1:0] data_in [0:PARALLEL_OUTPUTS-1];

    logic [NUM_OUTPUT_BUFFERS-1:0] wren;
    logic [NUM_OUTPUT_BUFFERS-1:0] rden;

    logic                  read_group_sel;
    logic [DATA_WIDTH-1:0] read_data [0:PARALLEL_OUTPUTS-1];


    //--------------------------------------------------------------------------
    // Independent golden model
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] ref_mem [0:NUM_OUTPUT_BUFFERS-1][0:DEPTH-1];
    logic [DATA_WIDTH-1:0] expected_read_data [0:PARALLEL_OUTPUTS-1];


    //--------------------------------------------------------------------------
    // Test status and coverage
    //--------------------------------------------------------------------------

    int unsigned errors;
    int unsigned check_count;

    bit group0_path_covered;
    bit group1_path_covered;
    bit ping_pong_0_to_1_covered;
    bit ping_pong_1_to_0_covered;
    bit consecutive_read_covered;
    bit async_reset_covered;


    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------

    output_buffer_bank #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) dut (
        .clk            (clk),
        .resetb         (resetb),
        .rd_addr        (rd_addr),
        .wr_addr        (wr_addr),
        .data_in        (data_in),
        .wren           (wren),
        .rden           (rden),
        .read_group_sel (read_group_sel),
        .read_data      (read_data)
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
    //--------------------------------------------------------------------------

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //--------------------------------------------------------------------------
    // Group mask helper
    //--------------------------------------------------------------------------

    function automatic mask_t group_mask(
        input logic group_sel
    );
        mask_t result;
        int unsigned lane_idx;
        int unsigned base_idx;

        begin
            result   = mask_t'(0);
            base_idx = group_sel ? PARALLEL_OUTPUTS : 0;

            for (lane_idx = 0;
                 lane_idx < PARALLEL_OUTPUTS;
                 lane_idx = lane_idx + 1)
                result[base_idx + lane_idx] = 1'b1;

            group_mask = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Initialize all driven inputs.
    //--------------------------------------------------------------------------

    task automatic clear_inputs;
        int unsigned lane_idx;

        begin
            rd_addr        = addr_t'(0);
            wr_addr        = addr_t'(0);
            wren           = mask_t'(0);
            rden           = mask_t'(0);
            read_group_sel = 1'b0;

            for (lane_idx = 0;
                 lane_idx < PARALLEL_OUTPUTS;
                 lane_idx = lane_idx + 1) begin
                data_in[lane_idx]            = data_t'(0);
                expected_read_data[lane_idx] = data_t'(0);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Initialize the independent reference memory.
    //--------------------------------------------------------------------------

    task automatic clear_reference_memory;
        int unsigned buffer_idx;
        int unsigned address_idx;

        begin
            for (buffer_idx = 0;
                 buffer_idx < NUM_OUTPUT_BUFFERS;
                 buffer_idx = buffer_idx + 1) begin

                for (address_idx = 0;
                     address_idx < DEPTH;
                     address_idx = address_idx + 1)
                    ref_mem[buffer_idx][address_idx] = data_t'(0);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Update the independent golden model for one externally applied write.
    // The two group mappings are written explicitly rather than inferred from
    // DUT internals.
    //--------------------------------------------------------------------------

    task automatic model_write_group(
        input logic                  group_sel,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] value0,
        input logic [DATA_WIDTH-1:0] value1,
        input logic [DATA_WIDTH-1:0] value2
    );
        begin
            if (~group_sel) begin
                ref_mem[0][address] = value0;
                ref_mem[1][address] = value1;
                ref_mem[2][address] = value2;
            end
            else begin
                ref_mem[3][address] = value0;
                ref_mem[4][address] = value1;
                ref_mem[5][address] = value2;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Load expected read_data from the independent reference memory.
    //--------------------------------------------------------------------------

    task automatic load_expected_read_data(
        input logic                  group_sel,
        input logic [ADDR_WIDTH-1:0] address
    );
        begin
            if (~group_sel) begin
                expected_read_data[0] = ref_mem[0][address];
                expected_read_data[1] = ref_mem[1][address];
                expected_read_data[2] = ref_mem[2][address];
            end
            else begin
                expected_read_data[0] = ref_mem[3][address];
                expected_read_data[1] = ref_mem[4][address];
                expected_read_data[2] = ref_mem[5][address];
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Write one complete three-lane word into one group and update the golden
    // model from the same externally applied transaction.
    //--------------------------------------------------------------------------

    task automatic write_group(
        input logic                  group_sel,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] value0,
        input logic [DATA_WIDTH-1:0] value1,
        input logic [DATA_WIDTH-1:0] value2
    );
        begin
            sync();

            wr_addr    = address;
            data_in[0] = value0;
            data_in[1] = value1;
            data_in[2] = value2;
            wren       = group_mask(group_sel);
            rden       = mask_t'(0);

            sync();

            model_write_group(group_sel, address, value0, value1, value2);
            wren = mask_t'(0);
        end
    endtask


    //--------------------------------------------------------------------------
    // Check read_data against the independent golden model.
    //--------------------------------------------------------------------------

    task automatic check_read_data(
        input string                 test_name,
        input logic                  group_sel,
        input logic [ADDR_WIDTH-1:0] address
    );
        begin
            load_expected_read_data(group_sel, address);
            check_count = check_count + 3;

            assert (read_data[0] === expected_read_data[0])
            else begin
                errors = errors + 1;
                $error("[%s] lane 0 expected=%0d got=%0d",
                       test_name, expected_read_data[0], read_data[0]);
            end

            assert (read_data[1] === expected_read_data[1])
            else begin
                errors = errors + 1;
                $error("[%s] lane 1 expected=%0d got=%0d",
                       test_name, expected_read_data[1], read_data[1]);
            end

            assert (read_data[2] === expected_read_data[2])
            else begin
                errors = errors + 1;
                $error("[%s] lane 2 expected=%0d got=%0d",
                       test_name, expected_read_data[2], read_data[2]);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Check that asynchronous reset clears the registered BRAM outputs.
    //--------------------------------------------------------------------------

    task automatic check_reset_clear(
        input string test_name
    );
        begin
            expected_read_data[0] = data_t'(0);
            expected_read_data[1] = data_t'(0);
            expected_read_data[2] = data_t'(0);
            check_count = check_count + 3;

            assert (read_data[0] === data_t'(0))
            else begin
                errors = errors + 1;
                $error("[%s] lane 0 expected reset value 0, got=%0d",
                       test_name, read_data[0]);
            end

            assert (read_data[1] === data_t'(0))
            else begin
                errors = errors + 1;
                $error("[%s] lane 1 expected reset value 0, got=%0d",
                       test_name, read_data[1]);
            end

            assert (read_data[2] === data_t'(0))
            else begin
                errors = errors + 1;
                $error("[%s] lane 2 expected reset value 0, got=%0d",
                       test_name, read_data[2]);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Read one complete group through the bank and mux.
    //--------------------------------------------------------------------------

    task automatic read_group(
        input string                 test_name,
        input logic                  group_sel,
        input logic [ADDR_WIDTH-1:0] address
    );
        begin
            sync();

            rd_addr        = address;
            read_group_sel = group_sel;
            wren           = mask_t'(0);
            rden           = group_mask(group_sel);

            sync();
            sync();

            check_read_data(test_name, group_sel, address);

            rden = mask_t'(0);

            if (group_sel)
                group1_path_covered = 1'b1;
            else
                group0_path_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------

    initial begin
        errors      = 0;
        check_count = 0;

        group0_path_covered         = 1'b0;
        group1_path_covered         = 1'b0;
        ping_pong_0_to_1_covered    = 1'b0;
        ping_pong_1_to_0_covered    = 1'b0;
        consecutive_read_covered    = 1'b0;
        async_reset_covered         = 1'b0;

        clear_inputs();
        clear_reference_memory();

        resetb = 1'b0;
        repeat (3) sync();

        resetb = 1'b1;
        sync();


        // ---------------------------------------------------------------------
        // TEST 1: Group 0 complete path.
        // ---------------------------------------------------------------------
        $display("TEST 1 - Group 0 complete path");
        write_group(1'b0, addr_t'(8), data_t'(10), data_t'(20), data_t'(30));
        read_group("TEST 1", 1'b0, addr_t'(8));


        // ---------------------------------------------------------------------
        // TEST 2: Group 1 complete path.
        // ---------------------------------------------------------------------
        $display("TEST 2 - Group 1 complete path");
        write_group(1'b1, addr_t'(18), data_t'(40), data_t'(50), data_t'(60));
        read_group("TEST 2", 1'b1, addr_t'(18));


        // ---------------------------------------------------------------------
        // TEST 3: Write group 1 while reading group 0.
        // ---------------------------------------------------------------------
        $display("TEST 3 - Ping-pong: write group 1, read group 0");

        sync();
        wr_addr        = addr_t'(28);
        rd_addr        = addr_t'(8);
        data_in[0]     = data_t'(70);
        data_in[1]     = data_t'(80);
        data_in[2]     = data_t'(90);
        wren           = group_mask(1'b1);
        rden           = group_mask(1'b0);
        read_group_sel = 1'b0;

        sync();
        model_write_group(1'b1, addr_t'(28),
                          data_t'(70), data_t'(80), data_t'(90));

        sync();
        check_read_data("TEST 3 READ", 1'b0, addr_t'(8));

        wren = mask_t'(0);
        rden = mask_t'(0);
        ping_pong_0_to_1_covered = 1'b1;

        read_group("TEST 3 WRITE CHECK", 1'b1, addr_t'(28));


        // ---------------------------------------------------------------------
        // TEST 4: Write group 0 while reading group 1.
        // ---------------------------------------------------------------------
        $display("TEST 4 - Ping-pong: write group 0, read group 1");

        sync();
        wr_addr        = addr_t'(38);
        rd_addr        = addr_t'(28);
        data_in[0]     = data_t'(100);
        data_in[1]     = data_t'(110);
        data_in[2]     = data_t'(120);
        wren           = group_mask(1'b0);
        rden           = group_mask(1'b1);
        read_group_sel = 1'b1;

        sync();
        model_write_group(1'b0, addr_t'(38),
                          data_t'(100), data_t'(110), data_t'(120));

        sync();
        check_read_data("TEST 4 READ", 1'b1, addr_t'(28));

        wren = mask_t'(0);
        rden = mask_t'(0);
        ping_pong_1_to_0_covered = 1'b1;

        read_group("TEST 4 WRITE CHECK", 1'b0, addr_t'(38));


        // ---------------------------------------------------------------------
        // TEST 5: Consecutive reads from group 0.
        // ---------------------------------------------------------------------
        $display("TEST 5 - Consecutive group 0 reads");

        write_group(1'b0, addr_t'(50), data_t'(1), data_t'(2), data_t'(3));
        write_group(1'b0, addr_t'(51), data_t'(4), data_t'(5), data_t'(6));
        write_group(1'b0, addr_t'(52), data_t'(7), data_t'(8), data_t'(9));

        sync();
        read_group_sel = 1'b0;
        wren           = mask_t'(0);
        rden           = group_mask(1'b0);
        rd_addr        = addr_t'(50);

        sync();
        rd_addr = addr_t'(51);

        sync();
        check_read_data("TEST 5A", 1'b0, addr_t'(50));
        rd_addr = addr_t'(52);

        sync();
        check_read_data("TEST 5B", 1'b0, addr_t'(51));
        rden = mask_t'(0);

        sync();
        check_read_data("TEST 5C", 1'b0, addr_t'(52));

        consecutive_read_covered = 1'b1;


        // ---------------------------------------------------------------------
        // TEST 6: Asynchronous reset.
        // ---------------------------------------------------------------------
        $display("TEST 6 - Asynchronous reset");

        write_group(1'b1, addr_t'(70), data_t'(131), data_t'(141), data_t'(151));
        read_group("TEST 6 BEFORE RESET", 1'b1, addr_t'(70));

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;

        check_reset_clear("TEST 6 RESET CLEAR");
        async_reset_covered = 1'b1;

        sync();
        resetb = 1'b1;
        sync();

        read_group("TEST 6 AFTER RESET", 1'b1, addr_t'(70));


        // ---------------------------------------------------------------------
        // Coverage checks.
        // ---------------------------------------------------------------------
        if (!group0_path_covered) begin
            $error("COVERAGE FAILED: group 0 complete path not covered");
            errors = errors + 1;
        end

        if (!group1_path_covered) begin
            $error("COVERAGE FAILED: group 1 complete path not covered");
            errors = errors + 1;
        end

        if (!ping_pong_0_to_1_covered) begin
            $error("COVERAGE FAILED: write group 1 / read group 0 not covered");
            errors = errors + 1;
        end

        if (!ping_pong_1_to_0_covered) begin
            $error("COVERAGE FAILED: write group 0 / read group 1 not covered");
            errors = errors + 1;
        end

        if (!consecutive_read_covered) begin
            $error("COVERAGE FAILED: consecutive reads not covered");
            errors = errors + 1;
        end

        if (!async_reset_covered) begin
            $error("COVERAGE FAILED: asynchronous reset not covered");
            errors = errors + 1;
        end


        // ---------------------------------------------------------------------
        // Final result.
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("--------------------------------------------------");
            $display("output_buffer_bank_tb PASSED");
            $display("Checks performed: %0d", check_count);
            $display("--------------------------------------------------");
        end
        else begin
            $error("output_buffer_bank_tb FAILED with %0d errors", errors);
        end

        #5;
        $stop;
    end

endmodule
