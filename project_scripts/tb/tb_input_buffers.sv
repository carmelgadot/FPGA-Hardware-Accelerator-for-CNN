`timescale 1ns / 1ps

//==============================================================================
// Testbench Name : tb_input_buffers
// Description    : Functional verification of the input_buffers module,
//                  which wraps multiple single-port BRAM instances.
//
// General Goals  :
//   - Verify correct write and read operations for individual buffers
//   - Verify independent operation of multiple buffers sharing buses
//   - Validate simultaneous multi-buffer read capability
//   - Check correct address selection between read and write modes
//   - Ensure stored data integrity across operations
//   - Verify safe behavior during concurrent read/write on different buffers
//   - Verify simultaneous read/write on the same buffer, including wr_addr
//     priority and NEW_DATA read-during-write behavior
//   - Verify consecutive reads from the same buffer at different addresses
//   - Validate asynchronous reset behavior (output clear without memory loss)
//   - Compare DUT outputs against a reference model (scoreboard)
//
// Methodology   :
//   - Uses sync() to align stimulus to posedges, except when demonstrating async-assert resetb
//   - Assertions for automatic pass/fail detection
//   - Reference memory model for expected values
//   - Waveform-friendly stimulus and monitoring
//==============================================================================

module tb_input_buffers;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter int DATA_WIDTH  = 8;
    parameter int ADDR_WIDTH  = 10;
    parameter int NUM_BUFFERS = 16;
    parameter int DEPTH       = (1 << ADDR_WIDTH);

    typedef logic [ADDR_WIDTH-1:0]  addr_t;
    typedef logic [DATA_WIDTH-1:0]  data_t;
    typedef logic [NUM_BUFFERS-1:0] mask_t;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    logic                          clk;
    logic                          resetb;
    logic [ADDR_WIDTH-1:0]         rd_addr;
    logic [ADDR_WIDTH-1:0]         wr_addr;
    logic [DATA_WIDTH-1:0]         data;
    logic [NUM_BUFFERS-1:0]        wren;
    logic [NUM_BUFFERS-1:0]        rden;
    logic [DATA_WIDTH-1:0]         q [0:NUM_BUFFERS-1];

    integer error_count;
    integer check_count;

    //==========================================================================
    // Reference Model / Scoreboard
    //==========================================================================
    logic [DATA_WIDTH-1:0] ref_mem [0:NUM_BUFFERS-1][0:DEPTH-1];

    //==========================================================================
    // DUT Instance
    //==========================================================================
    input_buffers #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_BUFFERS(NUM_BUFFERS)
    ) dut (
        .clk    (clk),
        .resetb (resetb),
        .rd_addr(rd_addr),
        .wr_addr(wr_addr),
        .data   (data),
        .wren   (wren),
        .rden   (rden),
        .q      (q)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //==========================================================================
    // Utility Tasks
    //==========================================================================

    //--------------------------------------------------------------------------
    // Task: sync
    // Description:
    //   Uses sync() to align to posedge and add small settle (#1ps), making
    //   stimulus change after the edge; DUT samples on the following edge;
    //   clean/deterministic timing.
    //--------------------------------------------------------------------------
    task automatic sync();
    begin
        @(posedge clk);
        #1ps;
    end
    endtask

    task automatic clear_inputs();
    begin
        rd_addr = addr_t'(0);
        wr_addr = addr_t'(0);
        data    = data_t'(0);
        wren    = mask_t'(0);
        rden    = mask_t'(0);
    end
    endtask

    task automatic init_reference_model();
        int i, j;
    begin
        for (i = 0; i < NUM_BUFFERS; i = i + 1)
            for (j = 0; j < DEPTH; j = j + 1)
                ref_mem[i][j] = data_t'(0);
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

    //--------------------------------------------------------------------------
    // Drive one cycle worth of inputs.
    // sync() is intentionally placed before changing the inputs, so the new
    // values are applied just after a posedge and are sampled by the DUT on the
    // following posedge.
    //--------------------------------------------------------------------------
    task automatic drive_cycle(
        input logic [ADDR_WIDTH-1:0]  rd_addr_in,
        input logic [ADDR_WIDTH-1:0]  wr_addr_in,
        input logic [DATA_WIDTH-1:0]  data_in,
        input logic [NUM_BUFFERS-1:0] wren_in,
        input logic [NUM_BUFFERS-1:0] rden_in
    );
    begin
        sync();
        rd_addr = rd_addr_in;
        wr_addr = wr_addr_in;
        data    = data_in;
        wren    = wren_in;
        rden    = rden_in;
    end
    endtask

    //--------------------------------------------------------------------------
    // Write one buffer and update scoreboard
    // Expected behavior:
    //   - write request is driven in one cycle
    //   - memory content is considered updated one clock later
    //--------------------------------------------------------------------------
    task automatic write_one_buffer(
        input int unsigned                buf_idx,
        input logic [ADDR_WIDTH-1:0]      addr_in,
        input logic [DATA_WIDTH-1:0]      data_in
    );
        logic [NUM_BUFFERS-1:0] wmask;
    begin
        wmask = mask_t'(0);
        wmask[buf_idx] = 1'b1;

        drive_cycle(addr_t'(0), addr_in, data_in, wmask, mask_t'(0));
        ref_mem[buf_idx][addr_in] = data_in;
    end
    endtask

    //--------------------------------------------------------------------------
    // Read selected buffers at one shared address
    // Expected behavior:
    //   - read request is driven in one cycle
    //   - DUT samples it on next clock
    //   - q is updated one more clock later because output is registered
    //--------------------------------------------------------------------------
    task automatic read_selected_buffers(
        input logic [ADDR_WIDTH-1:0]      addr_in,
        input logic [NUM_BUFFERS-1:0]     rden_mask
    );
    begin
        drive_cycle(addr_in, addr_t'(0), data_t'(0), mask_t'(0), rden_mask);

        // Two clocks after driving the read request:
        //   1) request is sampled
        //   2) registered output is updated
        sync();
        sync();
    end
    endtask

    //--------------------------------------------------------------------------
    // Check one buffer against scoreboard
    //--------------------------------------------------------------------------
    task automatic check_one_buffer(
        input string                      test_name,
        input int unsigned                buf_idx,
        input logic [ADDR_WIDTH-1:0]      addr_in
    );
        logic [DATA_WIDTH-1:0] expected;
    begin
        expected = ref_mem[buf_idx][addr_in];
        check_count = check_count + 1;

        assert (q[buf_idx] === expected)
        else begin
            error_count = error_count + 1;
            $error("[%s] FAILED: q[%0d] = %0d, expected = %0d at addr %0d",
                   test_name, buf_idx, q[buf_idx], expected, addr_in);
        end

        if (q[buf_idx] === expected)
            $display("[%s] PASS: q[%0d] = %0d at addr %0d",
                     test_name, buf_idx, q[buf_idx], addr_in);
    end
    endtask

    //--------------------------------------------------------------------------
    // Check all enabled buffers against scoreboard
    //--------------------------------------------------------------------------
    task automatic check_selected_buffers(
        input string                      test_name,
        input logic [ADDR_WIDTH-1:0]      addr_in,
        input logic [NUM_BUFFERS-1:0]     mask
    );
        int i;
        logic [DATA_WIDTH-1:0] expected;
    begin
        for (i = 0; i < NUM_BUFFERS; i = i + 1) begin
            if (mask[i]) begin
                expected = ref_mem[i][addr_in];
                check_count = check_count + 1;

                assert (q[i] === expected)
                else begin
                    error_count = error_count + 1;
                    $error("[%s] FAILED: q[%0d] = %0d, expected = %0d at addr %0d",
                           test_name, i, q[i], expected, addr_in);
                end

                if (q[i] === expected)
                    $display("[%s] PASS: q[%0d] = %0d at addr %0d",
                             test_name, i, q[i], addr_in);
            end
        end
    end
    endtask

    //--------------------------------------------------------------------------
    // Pretty print selected q values
    //--------------------------------------------------------------------------
    task automatic print_selected_outputs(
        input string                      title,
        input logic [NUM_BUFFERS-1:0]     mask
    );
        int i;
    begin
        $display("---- %s ----", title);
        for (i = 0; i < NUM_BUFFERS; i = i + 1) begin
            if (mask[i])
                $display("q[%0d] = %0d", i, q[i]);
        end
        $display("-----------------------------");
    end
    endtask

    //--------------------------------------------------------------------------
    // Monitor read results against scoreboard
    //--------------------------------------------------------------------------
    task automatic monitor_read_results(
        input logic [ADDR_WIDTH-1:0]      addr_in,
        input logic [NUM_BUFFERS-1:0]     mask
    );
        int i;
    begin
        $display("[MONITOR][READ_RSP] time=%0t  addr=%0d", $time, addr_in);
        for (i = 0; i < NUM_BUFFERS; i = i + 1) begin
            if (mask[i])
                $display("    buffer=%0d  q=%0d  expected=%0d",
                         i, q[i], ref_mem[i][addr_in]);
        end
    end
    endtask

    //==========================================================================
    // Wave / Transcript Monitor
    //==========================================================================

    // Write monitor
    always @(posedge clk) begin : write_monitor
        int i;
        if (resetb) begin
            for (i = 0; i < NUM_BUFFERS; i = i + 1) begin
                if (wren[i]) begin
                    $display("[MONITOR][WRITE] time=%0t  buffer=%0d  addr=%0d  data=%0d",
                             $time, i, wr_addr, data);
                end
            end
        end
    end

    // Read request monitor
    always @(posedge clk) begin : read_request_monitor
        int i;
        if (resetb) begin
            for (i = 0; i < NUM_BUFFERS; i = i + 1) begin
                if (rden[i]) begin
                    $display("[MONITOR][READ_REQ] time=%0t  buffer=%0d  addr=%0d",
                             $time, i, rd_addr);
                end
            end
        end
    end

    // Simultaneous read/write on the same BRAM is legal for this configuration.
    // When both enables are asserted, the write address must be selected.

    //==========================================================================
    // Optional Waveform Notes
    //==========================================================================
    initial begin
        $display("Waveform notes:");
        $display("  - sync() aligns stimulus changes just after posedge clk");
        $display("  - DUT samples on the following edge");
        $display("  - wr_addr/data/wren are used for write operations");
        $display("  - rd_addr/rden are used for read operations");
        $display("  - write is expected one clock after request");
        $display("  - q[] updates two clocks after read request because output is registered");
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        error_count = 0;
        check_count = 0;

        clear_inputs();
        init_reference_model();

        // ---------------------------------------------------------------------
        // RESET PHASE
        // Asynchronous reset is applied directly, without sync()
        // ---------------------------------------------------------------------
        resetb = 1'b0;
        repeat (3) sync();
        resetb = 1'b1;
        sync();
        sync();

        // ---------------------------------------------------------------------
        // TEST 1
        // Test procedure:
        //   - Writes value 165 to buffer 0 at address 3.
        //   - Reads buffer 0 from the same address.
        //   - Checks that q[0] matches the value stored in the reference model.
        // ---------------------------------------------------------------------
        print_banner("TEST 1 - Single write/read on buffer 0");
        write_one_buffer(0, addr_t'(3),  data_t'(165));
        read_selected_buffers(addr_t'(3), mask_t'(1));
        monitor_read_results(addr_t'(3), mask_t'(1));
        check_one_buffer("TEST 1", 0, addr_t'(3));

        // ---------------------------------------------------------------------
        // TEST 2
        // Test procedure:
        //   - Writes value 60 to buffer 5 at address 7.
        //   - Reads buffer 5 from the same address.
        //   - Checks that q[5] returns the written value correctly.
        // ---------------------------------------------------------------------
        print_banner("TEST 2 - Single write/read on buffer 5");
        write_one_buffer(5, addr_t'(7),  data_t'(60));
        read_selected_buffers(addr_t'(7), mask_t'(32));
        monitor_read_results(addr_t'(7), mask_t'(32));
        check_one_buffer("TEST 2", 5, addr_t'(7));

        // ---------------------------------------------------------------------
        // TEST 3
        // Test procedure:
        //   - Writes different values to buffers 1, 2 and 3 at the same address 12.
        //   - Enables reading of all three buffers simultaneously.
        //   - Checks that each buffer returns its own stored value independently.
        // ---------------------------------------------------------------------
        print_banner("TEST 3 - Same address in multiple buffers");
        write_one_buffer(1, addr_t'(12), data_t'(17));
        write_one_buffer(2, addr_t'(12), data_t'(34));
        write_one_buffer(3, addr_t'(12), data_t'(51));

        read_selected_buffers(addr_t'(12), mask_t'(14));
        monitor_read_results(addr_t'(12), mask_t'(14));
        print_selected_outputs("TEST 3 OUTPUTS", mask_t'(14));
        check_selected_buffers("TEST 3", addr_t'(12), mask_t'(14));

        // ---------------------------------------------------------------------
        // TEST 4
        // Test procedure:
        //   - Reads previously written data from buffer 0 at address 3.
        //   - Reads previously written data from buffer 5 at address 7.
        //   - Checks that earlier memory contents remain unchanged after other operations.
        // ---------------------------------------------------------------------
        print_banner("TEST 4 - Previous data remains intact");
        read_selected_buffers(addr_t'(3), mask_t'(1));
        monitor_read_results(addr_t'(3), mask_t'(1));
        check_one_buffer("TEST 4A", 0, addr_t'(3));

        read_selected_buffers(addr_t'(7), mask_t'(32));
        monitor_read_results(addr_t'(7), mask_t'(32));
        check_one_buffer("TEST 4B", 5, addr_t'(7));

        // ---------------------------------------------------------------------
        // TEST 5
        // Test procedure:
        //   - Enables buffers 1, 2 and 3 for reading at the same time.
        //   - Uses the shared read address 12 for all selected buffers.
        //   - Checks that all selected buffers return the expected data in parallel.
        // ---------------------------------------------------------------------
        print_banner("TEST 5 - Simultaneous multi-buffer read");
        read_selected_buffers(addr_t'(12), mask_t'(14));
        monitor_read_results(addr_t'(12), mask_t'(14));
        check_selected_buffers("TEST 5", addr_t'(12), mask_t'(14));

        // ---------------------------------------------------------------------
        // TEST 6
        // Test procedure:
        //   - Reads buffers 1, 2 and 3 from address 12 while writing value 102
        //     to buffer 6 at address 20 in the same cycle.
        //   - Checks that the read buffers return their expected data.
        //   - Reads buffer 6 afterward and verifies that the write was stored correctly.
        // ---------------------------------------------------------------------
        print_banner("TEST 6 - Write buffer 6 while reading buffers 1,2,3");

        drive_cycle(addr_t'(12), addr_t'(20), data_t'(102), mask_t'(64), mask_t'(14));
        ref_mem[6][addr_t'(20)] = data_t'(102);

        // One clock after write request -> update reference model for write
        sync();

        // One more clock -> read data appears because output is registered
        sync();
        monitor_read_results(addr_t'(12), mask_t'(14));
        check_selected_buffers("TEST 6A", addr_t'(12), mask_t'(14));

        read_selected_buffers(addr_t'(20), mask_t'(64));
        monitor_read_results(addr_t'(20), mask_t'(64));
        check_one_buffer("TEST 6B", 6, addr_t'(20));

        // ---------------------------------------------------------------------
        // TEST 7
        // Test procedure:
        //   - Writes different values to buffers 4 and 7 at address 31.
        //   - Reads both buffers simultaneously from the same address.
        //   - Checks that each buffer preserves and returns its own independent data.
        // ---------------------------------------------------------------------
        print_banner("TEST 7 - Multiple independent writes");
        write_one_buffer(4, addr_t'(31), data_t'(68));
        write_one_buffer(7, addr_t'(31), data_t'(119));

        read_selected_buffers(addr_t'(31), mask_t'(144));
        monitor_read_results(addr_t'(31), mask_t'(144));
        check_selected_buffers("TEST 7", addr_t'(31), mask_t'(144));

        // ---------------------------------------------------------------------
        // TEST 8
        // Test procedure:
        //   - Writes different values to buffers 0, 1, 2 and 3 at address 100.
        //   - Reads all four buffers simultaneously from address 100.
        //   - Checks that each buffer returns the value written specifically to it.
        // ---------------------------------------------------------------------
        print_banner("TEST 8 - Multiple independent writes to same address");
        write_one_buffer(0, addr_t'(100), data_t'(16));
        write_one_buffer(1, addr_t'(100), data_t'(33));
        write_one_buffer(2, addr_t'(100), data_t'(50));
        write_one_buffer(3, addr_t'(100), data_t'(67));

        read_selected_buffers(addr_t'(100), mask_t'(15));
        monitor_read_results(addr_t'(100), mask_t'(15));
        print_selected_outputs("TEST 8 OUTPUTS", mask_t'(15));
        check_selected_buffers("TEST 8", addr_t'(100), mask_t'(15));

        // ---------------------------------------------------------------------
        // TEST 9: Reset behavior
        // Test procedure:
        //   - Writes and reads a known value in buffer 2 before reset.
        //   - Asserts reset asynchronously between clock edges and checks that q[2]
        //     is cleared before the next active clock edge.
        //   - Releases reset and checks that the stored memory data was not erased.
        // Check that reset clears the BRAM output register but does not erase
        // the stored memory contents.
        // ---------------------------------------------------------------------
        print_banner("TEST 9 - Reset behavior during operation");

        // Write known value into buffer 2 at address 50
        write_one_buffer(2, addr_t'(50), data_t'(170));

        // Read before reset
        read_selected_buffers(addr_t'(50), mask_t'(4));
        monitor_read_results(addr_t'(50), mask_t'(4));
        check_one_buffer("TEST 9A - Before reset", 2, addr_t'(50));

        // Apply asynchronous reset directly (no sync)
        $display("[TEST 9] Applying asynchronous reset...");
        #2.5;
        resetb = 1'b0;

        // Check that q is cleared asynchronously, before the next clock edge
        #1;
        check_count = check_count + 1;
        assert (q[2] === data_t'(0))
        else begin
            error_count = error_count + 1;
            $error("[TEST 9] FAILED: asynchronous reset did not clear q[2]");
        end

        if (q[2] === data_t'(0))
            $display("[TEST 9] PASS: asynchronous reset cleared q[2] before the next clock edge");

        // Wait during reset
        repeat (2) sync();

        // Observe output during reset
        $display("[TEST 9] During reset: q[2] = %0d", q[2]);

        // Release reset directly (no sync)
        $display("[TEST 9] Releasing reset...");
        resetb = 1'b1;

        sync();
        sync();

        // Read again after reset: memory content should still be present
        read_selected_buffers(addr_t'(50), mask_t'(4));
        monitor_read_results(addr_t'(50), mask_t'(4));
        check_one_buffer("TEST 9B - After reset", 2, addr_t'(50));

        // ---------------------------------------------------------------------
        // TEST 10
        // Test procedure:
        //   - Writes value 88 to buffer 0 at address 200.
        //   - Drives a read from address 100 on the following cycle without an idle cycle.
        //   - Checks the read result from address 100 and then verifies the new data
        //     stored at address 200.
        // Write and read back-to-back on the same buffer, different addresses
        // ---------------------------------------------------------------------
        print_banner("TEST 10 - Back-to-back write then read on same buffer, different addresses");

        drive_cycle(addr_t'(0), addr_t'(200), data_t'(88), mask_t'(1), mask_t'(0));
        ref_mem[0][addr_t'(200)] = data_t'(88);

        drive_cycle(addr_t'(100), addr_t'(0), data_t'(0), mask_t'(0), mask_t'(1));
        sync();
        sync();
        monitor_read_results(addr_t'(100), mask_t'(1));
        check_one_buffer("TEST 10A", 0, addr_t'(100));

        read_selected_buffers(addr_t'(200), mask_t'(1));
        monitor_read_results(addr_t'(200), mask_t'(1));
        check_one_buffer("TEST 10B", 0, addr_t'(200));

        // ---------------------------------------------------------------------
        // TEST 11
        // Test procedure:
        //   - Reads buffers 1, 2 and 3 from address 12 while writing value 55
        //     to buffer 4 at address 300 in the same cycle.
        //   - Checks the simultaneous read results.
        //   - Reads buffer 4 afterward and verifies that the write completed correctly.
        // Simultaneous read and write on different buffers
        // ---------------------------------------------------------------------
        print_banner("TEST 11 - Simultaneous read and write on different buffers");

        drive_cycle(addr_t'(12), addr_t'(300), data_t'(55), mask_t'(16), mask_t'(14));
        ref_mem[4][addr_t'(300)] = data_t'(55);

        sync();
        sync();
        monitor_read_results(addr_t'(12), mask_t'(14));
        check_selected_buffers("TEST 11A", addr_t'(12), mask_t'(14));

        read_selected_buffers(addr_t'(300), mask_t'(16));
        monitor_read_results(addr_t'(300), mask_t'(16));
        check_one_buffer("TEST 11B", 4, addr_t'(300));

        // ---------------------------------------------------------------------
        // TEST 12
        // Test procedure:
        //   - Reads buffers 0, 1, 2 and 3 from address 100 while writing value 201
        //     to buffer 5 at address 222 in the same cycle.
        //   - Checks the simultaneous read results.
        //   - Reads buffer 5 afterward and verifies that the written value is stored.
        // Another simultaneous read and write on different buffers
        // ---------------------------------------------------------------------
        print_banner("TEST 12 - Another simultaneous read and write on different buffers");

        drive_cycle(addr_t'(100), addr_t'(222), data_t'(201), mask_t'(32), mask_t'(15));
        ref_mem[5][addr_t'(222)] = data_t'(201);

        sync();
        sync();
        monitor_read_results(addr_t'(100), mask_t'(15));
        check_selected_buffers("TEST 12A", addr_t'(100), mask_t'(15));

        read_selected_buffers(addr_t'(222), mask_t'(32));
        monitor_read_results(addr_t'(222), mask_t'(32));
        check_one_buffer("TEST 12B", 5, addr_t'(222));

        // ---------------------------------------------------------------------
        // TEST 13
        // Test procedure:
        //   - Initializes two different addresses in buffer 2.
        //   - Asserts wren and rden simultaneously for buffer 2 while rd_addr and
        //     wr_addr are different.
        //   - Checks that wr_addr is selected and that q[2] returns NEW_DATA.
        //   - Verifies that rd_addr remains unchanged and wr_addr contains the new value.
        // Simultaneous read and write on the same buffer.
        // Verify that wr_addr is selected and NEW_DATA is returned on q.
        // ---------------------------------------------------------------------
        print_banner("TEST 13 - Simultaneous read and write on same buffer");

        // Initialize different values at the read and write addresses.
        write_one_buffer(2, addr_t'(400), data_t'(45));
        write_one_buffer(2, addr_t'(401), data_t'(90));

        // Assert both enables for buffer 2 with different rd_addr and wr_addr.
        drive_cycle(addr_t'(400), addr_t'(401), data_t'(210),
                    mask_t'(4), mask_t'(4));

        // wren has priority in the address mux, so wr_addr must be selected.
        #1ps;
        check_count = check_count + 1;
        assert (dut.gen_input_buffer[2].bram_addr === addr_t'(401))
        else begin
            error_count = error_count + 1;
            $error("[TEST 13] FAILED: bram_addr = %0d, expected wr_addr = %0d",
                   dut.gen_input_buffer[2].bram_addr, addr_t'(401));
        end

        if (dut.gen_input_buffer[2].bram_addr === addr_t'(401))
            $display("[TEST 13] PASS: wr_addr is selected when wren and rden are both asserted");

        ref_mem[2][addr_t'(401)] = data_t'(210);

        // Wait for the registered read-during-write result.
        sync();
        sync();

        check_count = check_count + 1;
        assert (q[2] === data_t'(210))
        else begin
            error_count = error_count + 1;
            $error("[TEST 13] FAILED: q[2] = %0d, expected NEW_DATA = %0d",
                   q[2], data_t'(210));
        end

        if (q[2] === data_t'(210))
            $display("[TEST 13] PASS: simultaneous read/write returns NEW_DATA on q[2]");

        // Verify that rd_addr was not written and wr_addr contains the new data.
        read_selected_buffers(addr_t'(400), mask_t'(4));
        check_one_buffer("TEST 13A - rd_addr unchanged", 2, addr_t'(400));

        read_selected_buffers(addr_t'(401), mask_t'(4));
        check_one_buffer("TEST 13B - wr_addr updated", 2, addr_t'(401));

        // ---------------------------------------------------------------------
        // TEST 14
        // Test procedure:
        //   - Writes three different values to buffer 3 at addresses 500, 501 and 502.
        //   - Keeps rden asserted for buffer 3 throughout the read sequence.
        //   - Changes rd_addr on every consecutive clock cycle.
        //   - Checks that the outputs are returned on consecutive clock cycles
        //     in the expected order: 11, 22, 33.
        // ---------------------------------------------------------------------
        print_banner("TEST 14 - Consecutive reads from same buffer");

        // Initialize three consecutive addresses in buffer 3.
        write_one_buffer(3, addr_t'(500), data_t'(11));
        write_one_buffer(3, addr_t'(501), data_t'(22));
        write_one_buffer(3, addr_t'(502), data_t'(33));

        // Keep rden asserted and present a new read address every clock cycle.
        drive_cycle(addr_t'(500), addr_t'(0), data_t'(0), mask_t'(0), mask_t'(8));
        drive_cycle(addr_t'(501), addr_t'(0), data_t'(0), mask_t'(0), mask_t'(8));
        drive_cycle(addr_t'(502), addr_t'(0), data_t'(0), mask_t'(0), mask_t'(8));

        // After the pipeline fills, a new read result must appear every clock.
        check_one_buffer("TEST 14A", 3, addr_t'(500));

        sync();
        check_one_buffer("TEST 14B", 3, addr_t'(501));

        sync();
        check_one_buffer("TEST 14C", 3, addr_t'(502));

        // ---------------------------------------------------------------------
        // FINAL SUMMARY
        // ---------------------------------------------------------------------
        $display("");
        $display("================================================================");
        $display("SIMULATION SUMMARY");
        $display("  Total checks : %0d", check_count);
        $display("  Total errors : %0d", error_count);
        if (error_count == 0)
            $display("  RESULT       : PASS");
        else
            $display("  RESULT       : FAIL");
        $display("================================================================");
        $display("");

        #20;
        $stop;
    end

endmodule