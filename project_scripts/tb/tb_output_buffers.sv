`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : tb_output_buffers

  Description :
    Functional verification of output_buffers.

    The DUT contains six independent single-port BRAMs organized as two groups
    of three. Three convolution-result lanes are written in parallel to one
    group while the other group may be read in parallel.

  General Goals :
    - Verify parallel write/read of group 0.
    - Verify parallel write/read of group 1.
    - Verify correct lane-to-BRAM mapping.
    - Verify simultaneous write of one group and read of the other group.
    - Verify operation in both ping-pong directions.
    - Verify consecutive cycle-by-cycle reads from one group.
    - Verify asynchronous reset of BRAM outputs without erasing stored data.
    - Account for the registered BRAM read latency.

  Methodology :
    - Uses sync() before every normal stimulus change.
    - resetb assertion is intentionally asynchronous when reset behavior is tested.
    - Uses assertions and a reference-memory model for automatic checking.
*/
//==============================================================================

module tb_output_buffers;

    //--------------------------------------------------------------------------
    // Testbench parameters
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

    logic [DATA_WIDTH-1:0] q [0:NUM_OUTPUT_BUFFERS-1];


    //--------------------------------------------------------------------------
    // Reference model / status
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] ref_mem [0:NUM_OUTPUT_BUFFERS-1][0:DEPTH-1];

    int unsigned error_count;
    int unsigned check_count;

    bit group0_write_covered;
    bit group1_write_covered;
    bit group0_read_covered;
    bit group1_read_covered;
    bit simultaneous_0_to_1_covered;
    bit simultaneous_1_to_0_covered;
    bit consecutive_read_covered;
    bit async_reset_covered;


    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------

    output_buffers #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) dut (
        .clk     (clk),
        .resetb  (resetb),
        .rd_addr (rd_addr),
        .wr_addr (wr_addr),
        .data_in (data_in),
        .wren    (wren),
        .rden    (rden),
        .q       (q)
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
    // Return the three-bit physical mask of one output-buffer group.
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
    // Initialize inputs and reference memory.
    //--------------------------------------------------------------------------

    task automatic clear_inputs;
        int unsigned lane_idx;

        begin
            rd_addr = addr_t'(0);
            wr_addr = addr_t'(0);
            wren    = mask_t'(0);
            rden    = mask_t'(0);

            for (lane_idx = 0;
                 lane_idx < PARALLEL_OUTPUTS;
                 lane_idx = lane_idx + 1)
                data_in[lane_idx] = data_t'(0);
        end
    endtask


    task automatic init_reference_model;
        int unsigned buffer_idx;
        int unsigned address_idx;

        begin
            for (buffer_idx = 0;
                 buffer_idx < NUM_OUTPUT_BUFFERS;
                 buffer_idx = buffer_idx + 1)
                for (address_idx = 0;
                     address_idx < DEPTH;
                     address_idx = address_idx + 1)
                    ref_mem[buffer_idx][address_idx] = data_t'(0);
        end
    endtask


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
    // Check the three BRAM outputs belonging to one physical group.
    //--------------------------------------------------------------------------

    task automatic check_group(
        input string                     test_name,
        input logic                      group_sel,
        input logic [ADDR_WIDTH-1:0]     address
    );
        int unsigned lane_idx;
        int unsigned buffer_idx;
        int unsigned base_idx;

        begin
            base_idx = group_sel ? PARALLEL_OUTPUTS : 0;

            for (lane_idx = 0;
                 lane_idx < PARALLEL_OUTPUTS;
                 lane_idx = lane_idx + 1) begin

                buffer_idx = base_idx + lane_idx;
                check_count = check_count + 1;

                assert (q[buffer_idx] === ref_mem[buffer_idx][address])
                else begin
                    error_count = error_count + 1;
                    $error(
                        "[%s] group=%0d lane=%0d BRAM%0d address=%0d expected=%0d got=%0d",
                        test_name,
                        group_sel,
                        lane_idx,
                        buffer_idx,
                        address,
                        ref_mem[buffer_idx][address],
                        q[buffer_idx]
                    );
                end
            end

            if (group_sel)
                group1_read_covered = 1'b1;
            else
                group0_read_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Write all three lanes into one output-buffer group.
    //--------------------------------------------------------------------------

    task automatic write_group(
        input logic                      group_sel,
        input logic [ADDR_WIDTH-1:0]     address,
        input logic [DATA_WIDTH-1:0]     value0,
        input logic [DATA_WIDTH-1:0]     value1,
        input logic [DATA_WIDTH-1:0]     value2
    );
        int unsigned base_idx;

        begin
            sync();

            wr_addr    = address;
            data_in[0] = value0;
            data_in[1] = value1;
            data_in[2] = value2;
            wren       = group_mask(group_sel);
            rden       = mask_t'(0);

            sync();

            base_idx = group_sel ? PARALLEL_OUTPUTS : 0;
            ref_mem[base_idx + 0][address] = value0;
            ref_mem[base_idx + 1][address] = value1;
            ref_mem[base_idx + 2][address] = value2;

            wren = mask_t'(0);

            if (group_sel)
                group1_write_covered = 1'b1;
            else
                group0_write_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Read and check one complete three-BRAM group.
    // Two clock edges are allowed for the registered BRAM read path.
    //--------------------------------------------------------------------------

    task automatic read_group(
        input string                     test_name,
        input logic                      group_sel,
        input logic [ADDR_WIDTH-1:0]     address
    );
        begin
            sync();

            rd_addr = address;
            wren    = mask_t'(0);
            rden    = group_mask(group_sel);

            sync();
            sync();

            check_group(test_name, group_sel, address);

            rden = mask_t'(0);
        end
    endtask


    //--------------------------------------------------------------------------
    // Simultaneously write one group while reading the other.
    //--------------------------------------------------------------------------

    task automatic simultaneous_write_read(
        input string                     test_name,
        input logic                      write_group_sel,
        input logic                      read_group_sel,
        input logic [ADDR_WIDTH-1:0]     write_address,
        input logic [ADDR_WIDTH-1:0]     read_address,
        input logic [DATA_WIDTH-1:0]     value0,
        input logic [DATA_WIDTH-1:0]     value1,
        input logic [DATA_WIDTH-1:0]     value2
    );
        int unsigned write_base_idx;

        begin
            sync();

            wr_addr    = write_address;
            rd_addr    = read_address;
            data_in[0] = value0;
            data_in[1] = value1;
            data_in[2] = value2;
            wren       = group_mask(write_group_sel);
            rden       = group_mask(read_group_sel);

            sync();

            write_base_idx = write_group_sel ? PARALLEL_OUTPUTS : 0;
            ref_mem[write_base_idx + 0][write_address] = value0;
            ref_mem[write_base_idx + 1][write_address] = value1;
            ref_mem[write_base_idx + 2][write_address] = value2;

            sync();

            check_group(test_name, read_group_sel, read_address);

            wren = mask_t'(0);
            rden = mask_t'(0);

            if (write_group_sel)
                group1_write_covered = 1'b1;
            else
                group0_write_covered = 1'b1;

            if ((write_group_sel == 1'b1) && (read_group_sel == 1'b0))
                simultaneous_0_to_1_covered = 1'b1;

            if ((write_group_sel == 1'b0) && (read_group_sel == 1'b1))
                simultaneous_1_to_0_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------

    initial begin
        error_count = 0;
        check_count = 0;

        group0_write_covered           = 1'b0;
        group1_write_covered           = 1'b0;
        group0_read_covered            = 1'b0;
        group1_read_covered            = 1'b0;
        simultaneous_0_to_1_covered    = 1'b0;
        simultaneous_1_to_0_covered    = 1'b0;
        consecutive_read_covered       = 1'b0;
        async_reset_covered            = 1'b0;

        clear_inputs();
        init_reference_model();


        // Initial asynchronous reset.
        resetb = 1'b0;
        repeat (3) sync();

        // Reset release is synchronized.
        resetb = 1'b1;
        sync();


        // ---------------------------------------------------------------------
        // TEST 1: Parallel write/read of group 0.
        // ---------------------------------------------------------------------
        print_banner("TEST 1 - Parallel write/read of group 0");
        write_group(1'b0, addr_t'(10), data_t'(11), data_t'(22), data_t'(33));
        read_group("TEST 1", 1'b0, addr_t'(10));


        // ---------------------------------------------------------------------
        // TEST 2: Parallel write/read of group 1.
        // ---------------------------------------------------------------------
        print_banner("TEST 2 - Parallel write/read of group 1");
        write_group(1'b1, addr_t'(20), data_t'(44), data_t'(55), data_t'(66));
        read_group("TEST 2", 1'b1, addr_t'(20));


        // ---------------------------------------------------------------------
        // TEST 3: Write group 1 while reading group 0.
        // ---------------------------------------------------------------------
        print_banner("TEST 3 - Write group 1 while reading group 0");
        simultaneous_write_read(
            "TEST 3",
            1'b1,
            1'b0,
            addr_t'(30),
            addr_t'(10),
            data_t'(77),
            data_t'(88),
            data_t'(99)
        );
        read_group("TEST 3 WRITE CHECK", 1'b1, addr_t'(30));


        // ---------------------------------------------------------------------
        // TEST 4: Write group 0 while reading group 1.
        // ---------------------------------------------------------------------
        print_banner("TEST 4 - Write group 0 while reading group 1");
        simultaneous_write_read(
            "TEST 4",
            1'b0,
            1'b1,
            addr_t'(40),
            addr_t'(30),
            data_t'(101),
            data_t'(112),
            data_t'(123)
        );
        read_group("TEST 4 WRITE CHECK", 1'b0, addr_t'(40));


        // ---------------------------------------------------------------------
        // TEST 5: Consecutive cycle-by-cycle reads from group 0.
        // ---------------------------------------------------------------------
        print_banner("TEST 5 - Consecutive reads from group 0");

        write_group(1'b0, addr_t'(50), data_t'(10), data_t'(20), data_t'(30));
        write_group(1'b0, addr_t'(51), data_t'(40), data_t'(50), data_t'(60));
        write_group(1'b0, addr_t'(52), data_t'(70), data_t'(80), data_t'(90));

        sync();
        wren    = mask_t'(0);
        rden    = group_mask(1'b0);
        rd_addr = addr_t'(50);

        sync();
        rd_addr = addr_t'(51);

        sync();
        check_group("TEST 5A", 1'b0, addr_t'(50));
        rd_addr = addr_t'(52);

        sync();
        check_group("TEST 5B", 1'b0, addr_t'(51));
        rden = mask_t'(0);

        sync();
        check_group("TEST 5C", 1'b0, addr_t'(52));

        consecutive_read_covered = 1'b1;


        // ---------------------------------------------------------------------
        // TEST 6: Asynchronous reset clears outputs but preserves memory.
        // ---------------------------------------------------------------------
        print_banner("TEST 6 - Asynchronous reset behavior");

        write_group(1'b1, addr_t'(70), data_t'(131), data_t'(141), data_t'(151));
        read_group("TEST 6 BEFORE RESET", 1'b1, addr_t'(70));

        #(CLK_PERIOD / 4);
        resetb = 1'b0;
        #1ps;

        for (int buffer_idx = 0;
             buffer_idx < NUM_OUTPUT_BUFFERS;
             buffer_idx = buffer_idx + 1) begin

            check_count = check_count + 1;
            assert (q[buffer_idx] === data_t'(0))
            else begin
                error_count = error_count + 1;
                $error(
                    "TEST 6: asynchronous reset did not clear q[%0d]",
                    buffer_idx
                );
            end
        end

        async_reset_covered = 1'b1;

        // Synchronized reset release.
        sync();
        resetb = 1'b1;
        sync();

        // Stored BRAM contents must remain intact.
        read_group("TEST 6 AFTER RESET", 1'b1, addr_t'(70));


        // ---------------------------------------------------------------------
        // Coverage checks.
        // ---------------------------------------------------------------------
        if (!group0_write_covered) begin
            $error("COVERAGE FAILED: group 0 write not covered");
            error_count = error_count + 1;
        end

        if (!group1_write_covered) begin
            $error("COVERAGE FAILED: group 1 write not covered");
            error_count = error_count + 1;
        end

        if (!group0_read_covered) begin
            $error("COVERAGE FAILED: group 0 read not covered");
            error_count = error_count + 1;
        end

        if (!group1_read_covered) begin
            $error("COVERAGE FAILED: group 1 read not covered");
            error_count = error_count + 1;
        end

        if (!simultaneous_0_to_1_covered) begin
            $error("COVERAGE FAILED: write group 1 / read group 0 not covered");
            error_count = error_count + 1;
        end

        if (!simultaneous_1_to_0_covered) begin
            $error("COVERAGE FAILED: write group 0 / read group 1 not covered");
            error_count = error_count + 1;
        end

        if (!consecutive_read_covered) begin
            $error("COVERAGE FAILED: consecutive reads not covered");
            error_count = error_count + 1;
        end

        if (!async_reset_covered) begin
            $error("COVERAGE FAILED: asynchronous reset not covered");
            error_count = error_count + 1;
        end


        // ---------------------------------------------------------------------
        // Final test result.
        // ---------------------------------------------------------------------
        if (error_count == 0) begin
            $display("--------------------------------------------------");
            $display("tb_output_buffers PASSED");
            $display("Checks performed: %0d", check_count);
            $display("--------------------------------------------------");
        end
        else begin
            $error("tb_output_buffers FAILED with %0d errors", error_count);
        end

        #5;
        $stop;
    end

endmodule
