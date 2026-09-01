`timescale 1ns / 1ps

//==============================================================================
/*
  Testbench Name : tb_BRAM

  Description :
    Demonstration testbench for the Intel/Altera BRAM IP instance.

    BRAM.v is a Quartus-generated altsyncram IP file. Therefore this testbench
    is not intended to verify the internal implementation of the vendor IP.
    Its purpose is to demonstrate and document the externally visible behavior
    used by the project.

  Demonstration goals:
    - Demonstrate a basic write followed by a read.
    - Demonstrate the registered read-output latency.
    - Demonstrate consecutive reads from different addresses.
    - Demonstrate read-during-write behavior for the same address.
    - Demonstrate asynchronous clearing of the registered output using aclr.
    - Demonstrate that clearing q does not erase the stored memory contents.

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes are made only after sync() returns.
    - aclr assertion is intentionally applied between clock edges to
      demonstrate asynchronous output clearing.
*/
//==============================================================================

module tb_BRAM;

    //==========================================================================
    // Parameters
    //==========================================================================

    localparam int DATA_WIDTH = 8;
    localparam int ADDR_WIDTH = 10;
    localparam time CLK_PERIOD = 10ns;

    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;

    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic                  aclr;
    logic [ADDR_WIDTH-1:0] address;
    logic                  clock;
    logic [DATA_WIDTH-1:0] data;
    logic                  rden;
    logic                  wren;
    logic [DATA_WIDTH-1:0] q;

    int unsigned error_count;
    int unsigned check_count;

    logic basic_write_read_covered;
    logic registered_read_covered;
    logic consecutive_reads_covered;
    logic read_during_write_covered;
    logic async_clear_covered;
    logic memory_retention_covered;

    //==========================================================================
    // DUT Instance
    //==========================================================================

    BRAM dut (
        .aclr    (aclr),
        .address (address),
        .clock   (clock),
        .data    (data),
        .rden    (rden),
        .wren    (wren),
        .q       (q)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial clock = 1'b0;
    always #(CLK_PERIOD/2) clock = ~clock;

    //==========================================================================
    // Utility Tasks
    //==========================================================================

    //--------------------------------------------------------------------------
    // Synchronization task
    //
    // Normal stimulus is changed immediately after sync() returns.
    // aclr assertion is intentionally excluded when asynchronous behavior
    // is being demonstrated.
    //--------------------------------------------------------------------------
    task automatic sync;
        begin
            @(posedge clock);
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

    task automatic check_q(
        input string test_name,
        input data_t expected
    );
        begin
            check_count = check_count + 1;

            assert (q === expected)
            else begin
                error_count = error_count + 1;
                $error("[%s] FAILED: q = %0d (0x%0h), expected = %0d (0x%0h)",
                       test_name, q, q, expected, expected);
            end

            if (q === expected)
                $display("[%s] PASS: q = %0d (0x%0h)",
                         test_name, q, q);
        end
    endtask

    task automatic write_word(
        input addr_t addr_in,
        input data_t data_in
    );
        begin
            sync();
            address = addr_in;
            data    = data_in;
            wren    = 1'b1;
            rden    = 1'b0;

            sync();
            wren = 1'b0;
        end
    endtask

    task automatic issue_read(input addr_t addr_in);
        begin
            sync();
            address = addr_in;
            wren    = 1'b0;
            rden    = 1'b1;
        end
    endtask

    //==========================================================================
    // Main Demonstration Sequence
    //==========================================================================

    initial begin
        error_count = 0;
        check_count = 0;

        basic_write_read_covered = 1'b0;
        registered_read_covered  = 1'b0;
        consecutive_reads_covered = 1'b0;
        read_during_write_covered = 1'b0;
        async_clear_covered       = 1'b0;
        memory_retention_covered  = 1'b0;

        aclr    = 1'b0;
        address = addr_t'(0);
        data    = data_t'(0);
        rden    = 1'b0;
        wren    = 1'b0;

        //======================================================================
        // TEST 1
        // Basic write/read and registered read latency
        //
        // Write 8'hA5 to address 10, then issue a read. q is expected to update
        // only after the registered BRAM read path has completed.
        //======================================================================

        print_banner("TEST 1 - Basic write/read and registered output");

        write_word(addr_t'(10), data_t'(8'hA5));
        issue_read(addr_t'(10));

        sync();
        sync();
        check_q("TEST 1", data_t'(8'hA5));

        basic_write_read_covered = 1'b1;
        registered_read_covered  = 1'b1;

        //======================================================================
        // TEST 2
        // Consecutive reads
        //
        // Store three values, keep rden asserted, and change address on
        // consecutive cycles. The output sequence demonstrates the registered
        // pipeline behavior of the BRAM.
        //======================================================================

        print_banner("TEST 2 - Consecutive reads");

        write_word(addr_t'(20), data_t'(8'h11));
        write_word(addr_t'(21), data_t'(8'h22));
        write_word(addr_t'(22), data_t'(8'h33));

        sync();
        address = addr_t'(20);
        rden    = 1'b1;
        wren    = 1'b0;

        sync();
        address = addr_t'(21);

        sync();
        address = addr_t'(22);
        check_q("TEST 2A", data_t'(8'h11));

        sync();
        rden = 1'b0;
        check_q("TEST 2B", data_t'(8'h22));

        sync();
        check_q("TEST 2C", data_t'(8'h33));

        consecutive_reads_covered = 1'b1;

        //======================================================================
        // TEST 3
        // Read-during-write to the same address
        //
        // BRAM.v is configured with NEW_DATA_NO_NBE_READ. Therefore a cycle in
        // which read and write are both enabled for the same address returns
        // the newly written value after the registered read latency.
        //======================================================================

        print_banner("TEST 3 - Same-address read during write");

        write_word(addr_t'(30), data_t'(8'h44));

        sync();
        address = addr_t'(30);
        data    = data_t'(8'h99);
        wren    = 1'b1;
        rden    = 1'b1;

        sync();
        wren = 1'b0;
        rden = 1'b0;

        sync();
        check_q("TEST 3", data_t'(8'h99));

        read_during_write_covered = 1'b1;

        //======================================================================
        // TEST 4
        // Asynchronous output clear and memory retention
        //
        // aclr clears only the registered output. The memory contents remain
        // stored and can be read again after aclr is released.
        //======================================================================

        print_banner("TEST 4 - Asynchronous clear and retained memory");

        issue_read(addr_t'(10));
        sync();
        sync();
        check_q("TEST 4A - Before aclr", data_t'(8'hA5));

        // Assert aclr between edges to demonstrate asynchronous behavior.
        #(CLK_PERIOD/4);
        aclr = 1'b1;
        #1ps;
        check_q("TEST 4B - Asynchronous q clear", data_t'(0));
        async_clear_covered = 1'b1;

        // Release aclr only after synchronization.
        sync();
        aclr = 1'b0;
        rden = 1'b0;

        issue_read(addr_t'(10));
        sync();
        sync();
        check_q("TEST 4C - Memory retained", data_t'(8'hA5));
        memory_retention_covered = 1'b1;

        //======================================================================
        // Coverage / Final Summary
        //======================================================================

        check_count = check_count + 1;
        assert (basic_write_read_covered       &&
                registered_read_covered        &&
                consecutive_reads_covered      &&
                read_during_write_covered      &&
                async_clear_covered            &&
                memory_retention_covered)
        else begin
            error_count = error_count + 1;
            $error("Coverage flags are incomplete");
        end

        $display("");
        $display("================================================================");
        $display("SIMULATION SUMMARY - tb_BRAM");
        $display("Checks : %0d", check_count);
        $display("Errors : %0d", error_count);
        $display("================================================================");

        if (error_count == 0)
            $display("RESULT: PASSED - BRAM behavior demonstration completed");
        else
            $fatal(1, "RESULT: FAILED - %0d error(s)", error_count);

        $finish;
    end

endmodule
