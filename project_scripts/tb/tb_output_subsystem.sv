`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : tb_output_subsystem

  Description :
    Self-checking integration testbench for output_subsystem.

    The DUT contains both the output-buffer controller and the physical
    ping-pong output-buffer bank.

  Independent golden-model methodology:
    - The golden model does NOT reproduce the DUT FSM, address counters,
      BRAM-enable generation, group-selection logic, or internal BRAM structure.
    - Every externally supplied valid convolution-result transaction is stored
      only in a simple expected transaction list.
    - Whenever the DUT asserts out_valid, the returned three-lane read_data is
      compared with the next transaction in that list.
    - Therefore, the expected data/order is derived only from the externally
      driven input stream, not from the RTL implementation.

  Test goals:
    - Verify asynchronous active-low reset behavior.
    - Verify that no output is produced before the first complete group is full.
    - Verify end-to-end storage and readback of all parallel lanes.
    - Verify that conv_valid gaps do not create extra stored transactions.
    - Verify continuous writes into the second group.
    - Verify ping-pong group order.
    - Verify reuse of group 0 after group 1 has been drained.
    - Verify that out_valid is aligned with the corresponding read_data.
    - Verify that no expected output transaction is duplicated or lost.

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes are made only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges to verify
      asynchronous reset behavior.
*/
//==============================================================================

module tb_output_subsystem;

    //==========================================================================
    // Testbench Parameters
    //==========================================================================

    localparam int DATA_WIDTH         = 8;
    localparam int OUTPUT_LENGTH      = 4;
    localparam int ADDR_WIDTH         = 4;
    localparam int NUM_OUTPUT_BUFFERS = 6;
    localparam int PARALLEL_OUTPUTS   = 3;
    localparam int BRAM_READ_LATENCY  = 2;

    localparam int NUM_TEST_GROUPS      = 3;
    localparam int TOTAL_TRANSACTIONS   = NUM_TEST_GROUPS * OUTPUT_LENGTH;
    localparam int FIRST_TWO_GROUPS_END = 2 * OUTPUT_LENGTH;

    localparam time CLK_PERIOD = 10ns;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;

    logic                          conv_valid;
    logic [DATA_WIDTH-1:0]         data_in   [0:PARALLEL_OUTPUTS-1];

    logic [DATA_WIDTH-1:0]         read_data [0:PARALLEL_OUTPUTS-1];
    logic                          out_valid;


    //==========================================================================
    // Independent Golden Model
    //
    // The model is intentionally just an ordered list of input transactions.
    // It contains no model of the DUT FSM, counters, BRAM groups, or addresses.
    //==========================================================================

    logic [DATA_WIDTH-1:0] expected_lane0 [0:TOTAL_TRANSACTIONS-1];
    logic [DATA_WIDTH-1:0] expected_lane1 [0:TOTAL_TRANSACTIONS-1];
    logic [DATA_WIDTH-1:0] expected_lane2 [0:TOTAL_TRANSACTIONS-1];

    int unsigned expected_count;
    int unsigned received_count;


    //==========================================================================
    // Test Status / Coverage
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;

    bit async_reset_covered;
    bit initial_fill_no_output_covered;
    bit conv_valid_gap_covered;
    bit continuous_write_covered;
    bit first_group_read_covered;
    bit second_group_read_covered;
    bit group_reuse_covered;
    bit all_outputs_received_covered;


    //==========================================================================
    // DUT
    //==========================================================================

    output_subsystem #(
        .DATA_WIDTH         (DATA_WIDTH),
        .OUTPUT_LENGTH      (OUTPUT_LENGTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS),
        .BRAM_READ_LATENCY  (BRAM_READ_LATENCY)
    ) dut (
        .clk        (clk),
        .resetb     (resetb),

        .conv_valid (conv_valid),
        .data_in    (data_in),

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
    //
    // Normal stimulus is changed immediately after sync() returns.
    // resetb assertion is intentionally excluded when asynchronous behavior
    // is being tested.
    //==========================================================================

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //==========================================================================
    // Golden-Model Helpers
    //==========================================================================

    //----------------------------------------------------------------------
    // Store one expected external transaction.
    //----------------------------------------------------------------------
    task automatic record_expected(
        input logic [DATA_WIDTH-1:0] lane0,
        input logic [DATA_WIDTH-1:0] lane1,
        input logic [DATA_WIDTH-1:0] lane2
    );
        begin
            if (expected_count >= TOTAL_TRANSACTIONS) begin
                $error("Golden-model overflow");
                error_count = error_count + 1;
            end
            else begin
                expected_lane0[expected_count] = lane0;
                expected_lane1[expected_count] = lane1;
                expected_lane2[expected_count] = lane2;
                expected_count = expected_count + 1;
            end
        end
    endtask


    //----------------------------------------------------------------------
    // Drive one valid transaction for exactly one active clock edge.
    //----------------------------------------------------------------------
    task automatic send_one_transaction(
        input logic [DATA_WIDTH-1:0] lane0,
        input logic [DATA_WIDTH-1:0] lane1,
        input logic [DATA_WIDTH-1:0] lane2
    );
        begin
            sync();

            data_in[0] = lane0;
            data_in[1] = lane1;
            data_in[2] = lane2;
            conv_valid = 1'b1;

            record_expected(lane0, lane1, lane2);

            // Transaction is sampled on this next active edge.
            sync();
            conv_valid = 1'b0;
        end
    endtask


    //----------------------------------------------------------------------
    // Drive one complete group continuously, one transaction per clock.
    //----------------------------------------------------------------------
    task automatic send_continuous_group(
        input int unsigned base_value
    );
        int unsigned tx;
        logic [DATA_WIDTH-1:0] lane0;
        logic [DATA_WIDTH-1:0] lane1;
        logic [DATA_WIDTH-1:0] lane2;

        begin
            sync();

            conv_valid = 1'b1;

            for (tx = 0; tx < OUTPUT_LENGTH; tx = tx + 1) begin
                lane0 = base_value + tx;
                lane1 = base_value + 40 + tx;
                lane2 = base_value + 80 + tx;

                data_in[0] = lane0;
                data_in[1] = lane1;
                data_in[2] = lane2;

                record_expected(lane0, lane1, lane2);

                sync();
            end

            conv_valid = 1'b0;
        end
    endtask


    //----------------------------------------------------------------------
    // Wait until a requested number of output transactions has been checked.
    //----------------------------------------------------------------------
    task automatic wait_for_received(
        input int unsigned target_count,
        input int unsigned timeout_cycles
    );
        int unsigned waited;

        begin
            waited = 0;

            while ((received_count < target_count) &&
                   (waited < timeout_cycles)) begin
                sync();
                waited = waited + 1;
            end

            if (received_count < target_count) begin
                $error(
                    "Timeout waiting for outputs: received=%0d target=%0d",
                    received_count,
                    target_count
                );
                error_count = error_count + 1;
            end
        end
    endtask


    //==========================================================================
    // Output Monitor / Scoreboard
    //
    // Only the external interface is checked. The monitor never uses internal
    // FSM state, counters, BRAM enables, or group-selection signals to compute
    // the expected result.
    //==========================================================================

    always @(posedge clk) begin
        #1ps;

        if (resetb && out_valid) begin

            check_count = check_count + 1;

            if (received_count >= expected_count) begin
                $error(
                    "[%0t] Unexpected output transaction: no golden entry exists",
                    $time
                );
                error_count = error_count + 1;
            end
            else begin
                if (read_data[0] !== expected_lane0[received_count]) begin
                    $error(
                        "[%0t] Lane 0 mismatch at transaction %0d: expected=%0d got=%0d",
                        $time,
                        received_count,
                        expected_lane0[received_count],
                        read_data[0]
                    );
                    error_count = error_count + 1;
                end

                if (read_data[1] !== expected_lane1[received_count]) begin
                    $error(
                        "[%0t] Lane 1 mismatch at transaction %0d: expected=%0d got=%0d",
                        $time,
                        received_count,
                        expected_lane1[received_count],
                        read_data[1]
                    );
                    error_count = error_count + 1;
                end

                if (read_data[2] !== expected_lane2[received_count]) begin
                    $error(
                        "[%0t] Lane 2 mismatch at transaction %0d: expected=%0d got=%0d",
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
                        "[%0t] PASS output transaction %0d : {%0d, %0d, %0d}",
                        $time,
                        received_count,
                        read_data[0],
                        read_data[1],
                        read_data[2]
                    );
                end
            end

            // Coverage by externally observed transaction order.
            if (received_count < OUTPUT_LENGTH)
                first_group_read_covered = 1'b1;
            else if (received_count < FIRST_TWO_GROUPS_END)
                second_group_read_covered = 1'b1;
            else
                group_reuse_covered = 1'b1;

            received_count = received_count + 1;
        end
    end


    //==========================================================================
    // Test Sequence
    //==========================================================================

    initial begin
        //----------------------------------------------------------------------
        // Initialization
        //----------------------------------------------------------------------
        resetb    = 1'b1;
        conv_valid = 1'b0;

        data_in[0] = '0;
        data_in[1] = '0;
        data_in[2] = '0;

        expected_count = 0;
        received_count = 0;
        error_count     = 0;
        check_count     = 0;

        async_reset_covered            = 1'b0;
        initial_fill_no_output_covered = 1'b0;
        conv_valid_gap_covered         = 1'b0;
        continuous_write_covered       = 1'b0;
        first_group_read_covered       = 1'b0;
        second_group_read_covered      = 1'b0;
        group_reuse_covered            = 1'b0;
        all_outputs_received_covered   = 1'b0;


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

        // Reset deassertion is synchronized by testbench convention.
        sync();
        resetb = 1'b1;


        //======================================================================
        // TEST 2: Initial group-0 fill with a conv_valid gap
        //
        // Only three transactions are written first. No output is allowed yet
        // because one complete output group has not been filled.
        //======================================================================

        send_one_transaction(8'd10,  8'd50,  8'd90);
        send_one_transaction(8'd11,  8'd51,  8'd91);

        // Explicit idle cycle: must not create a stored output transaction.
        sync();
        conv_valid = 1'b0;
        data_in[0] = 8'd200;
        data_in[1] = 8'd201;
        data_in[2] = 8'd202;
        conv_valid_gap_covered = 1'b1;

        sync();

        send_one_transaction(8'd12,  8'd52,  8'd92);

        if (out_valid !== 1'b0) begin
            $error("Output became valid before initial group 0 was full");
            error_count = error_count + 1;
        end
        else begin
            initial_fill_no_output_covered = 1'b1;
        end

        // Final transaction completes group 0.
        send_one_transaction(8'd13,  8'd53,  8'd93);


        //======================================================================
        // TEST 3: Fill group 1 continuously while group 0 is read
        //
        // Continuous valid cycles intentionally exercise one-result-per-clock
        // output-buffer writes.
        //======================================================================

        send_continuous_group(100);
        continuous_write_covered = 1'b1;

        // Both first groups must eventually be returned in original input order.
        wait_for_received(FIRST_TWO_GROUPS_END, 40);


        //======================================================================
        // TEST 4: Reuse group 0 after group 1 has been drained
        //
        // By the time eight outputs have been observed, both previously written
        // groups have been read. Writing another complete group therefore checks
        // ping-pong reuse without reproducing any internal group-state logic.
        //======================================================================

        send_continuous_group(180);

        wait_for_received(TOTAL_TRANSACTIONS, 40);

        if (received_count == TOTAL_TRANSACTIONS)
            all_outputs_received_covered = 1'b1;


        //======================================================================
        // TEST 5: Runtime asynchronous reset
        //======================================================================

        #2.5ns;
        resetb = 1'b0;
        #1ns;

        if (out_valid !== 1'b0) begin
            $error("Runtime asynchronous reset did not clear out_valid");
            error_count = error_count + 1;
        end

        sync();
        resetb = 1'b1;

        sync();


        //======================================================================
        // Final Checks / Coverage
        //======================================================================

        if (expected_count != TOTAL_TRANSACTIONS) begin
            $error(
                "Golden-model transaction count mismatch: expected_count=%0d",
                expected_count
            );
            error_count = error_count + 1;
        end

        if (received_count != TOTAL_TRANSACTIONS) begin
            $error(
                "DUT returned %0d transactions, expected %0d",
                received_count,
                TOTAL_TRANSACTIONS
            );
            error_count = error_count + 1;
        end

        if (!async_reset_covered ||
            !initial_fill_no_output_covered ||
            !conv_valid_gap_covered ||
            !continuous_write_covered ||
            !first_group_read_covered ||
            !second_group_read_covered ||
            !group_reuse_covered ||
            !all_outputs_received_covered) begin

            $error("Coverage failure: one or more directed behaviors were not exercised");
            error_count = error_count + 1;
        end


        $display("");
        $display("==============================================================");
        $display("tb_output_subsystem summary");
        $display("--------------------------------------------------------------");
        $display("Checks performed:                  %0d", check_count);
        $display("Expected input transactions:       %0d", expected_count);
        $display("Received output transactions:      %0d", received_count);
        $display("Async reset covered:               %0d", async_reset_covered);
        $display("Initial no-output covered:         %0d", initial_fill_no_output_covered);
        $display("conv_valid gap covered:            %0d", conv_valid_gap_covered);
        $display("Continuous writes covered:         %0d", continuous_write_covered);
        $display("Group 0 read covered:              %0d", first_group_read_covered);
        $display("Group 1 read covered:              %0d", second_group_read_covered);
        $display("Ping-pong group reuse covered:     %0d", group_reuse_covered);
        $display("All outputs received covered:      %0d", all_outputs_received_covered);
        $display("Errors:                            %0d", error_count);
        $display("==============================================================");

        if (error_count == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");

        $finish;
    end


endmodule
