`timescale 1ns/1ps

/*==============================================================================
  Testbench: tb_output_buffer_controller
  Purpose:
    Directed functional verification of output_buffer_controller.

    The test uses a short output length so complete ping-pong phases can be
    exercised quickly while preserving the controller behavior used by the
    full design.

  Independent golden-model methodology:
    - The golden model does NOT reproduce the DUT RTL structure.
    - It does not instantiate a second FSM, counter, or copy of the DUT case
      statements.
    - Instead it models the output subsystem as two abstract storage groups:
        * one group accepts valid convolution-result transactions
        * one completed group issues sequential read transactions
        * a group changes role only after the current writer is full and the
          current reader has fully drained
    - Write and read addresses are derived from independent transaction counts.
    - BRAM read latency is modeled with independent request-history pipelines.
    - Expected BRAM-enable masks are derived from the abstract active groups.

  Checks covered:
    - asynchronous active-low reset
    - write-address advance only on accepted conv_valid cycles
    - write counter hold across conv_valid gaps
    - correct three-BRAM write-group enable masks
    - initial fill of group 0 before any reads begin
    - continuous read-address generation for the active read group
    - correct three-BRAM read-group enable masks
    - BRAM read-latency alignment of out_valid
    - read drain after the final read request
    - no extra read request while the final read is pending
    - ping-pong group exchange
    - read-finishes-first / write-only operation
    - write-finishes-first / wait-read operation
    - simultaneous write/read completion
    - asynchronous reset during active ping-pong operation

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal conv_valid changes are made only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges to verify
      asynchronous reset behavior.
==============================================================================*/

module tb_output_buffer_controller;

  //--------------------------------------------------------------------------
  // Test parameters
  //--------------------------------------------------------------------------
  localparam int TB_OUTPUT_LENGTH       = 4;
  localparam int TB_ADDR_WIDTH          = 4;
  localparam int TB_NUM_OUTPUT_BUFFERS  = 6;
  localparam int TB_PARALLEL_OUTPUTS    = 3;
  localparam int TB_BRAM_READ_LATENCY   = 2;

  localparam time CLK_PERIOD = 10ns;

  localparam logic [TB_NUM_OUTPUT_BUFFERS-1:0] ZERO_MASK = '0;
  localparam logic [TB_NUM_OUTPUT_BUFFERS-1:0] GROUP0_MASK =
      {{TB_PARALLEL_OUTPUTS{1'b0}}, {TB_PARALLEL_OUTPUTS{1'b1}}};
  localparam logic [TB_NUM_OUTPUT_BUFFERS-1:0] GROUP1_MASK =
      {{TB_PARALLEL_OUTPUTS{1'b1}}, {TB_PARALLEL_OUTPUTS{1'b0}}};

  // FSM encodings are repeated only for readable observation/coverage.
  localparam logic [2:0]
      ST_FILL_GROUP0  = 3'd0,
      ST_WRITE1_READ0 = 3'd1,
      ST_WRITE1_ONLY  = 3'd2,
      ST_WAIT_READ0   = 3'd3,
      ST_WRITE0_READ1 = 3'd4,
      ST_WRITE0_ONLY  = 3'd5,
      ST_WAIT_READ1   = 3'd6;

  //--------------------------------------------------------------------------
  // Clock / Reset / Stimulus
  //--------------------------------------------------------------------------
  logic clk        = 1'b0;
  logic resetb     = 1'b1;
  logic conv_valid = 1'b0;

  //--------------------------------------------------------------------------
  // DUT outputs
  //--------------------------------------------------------------------------
  logic [TB_ADDR_WIDTH-1:0]          wr_addr;
  logic [TB_ADDR_WIDTH-1:0]          rd_addr;
  logic [TB_NUM_OUTPUT_BUFFERS-1:0]  bram_wr_en;
  logic [TB_NUM_OUTPUT_BUFFERS-1:0]  bram_rd_en;
  logic                              read_group_sel;
  logic                              out_valid;

  //--------------------------------------------------------------------------
  // Internal DUT observation - debug/coverage only
  //--------------------------------------------------------------------------
  logic       dut_en_write;
  logic       dut_en_read;
  logic       dut_write_group_sel;
  logic       dut_wr_valid;
  logic       dut_rd_valid;
  logic       dut_write_done;
  logic       dut_last_read_issued;
  logic       dut_read_pending;
  logic       dut_read_done;
  logic [2:0] dut_state;

  assign dut_en_write         = dut.en_write;
  assign dut_en_read          = dut.en_read;
  assign dut_write_group_sel  = dut.write_group_sel;
  assign dut_wr_valid         = dut.wr_valid;
  assign dut_rd_valid         = dut.rd_valid;
  assign dut_write_done       = dut.write_done;
  assign dut_last_read_issued = dut.last_read_issued;
  assign dut_read_pending     = dut.read_pending;
  assign dut_read_done        = dut.read_done;
  assign dut_state            = dut.u_output_buffer_fsm.state;

  //--------------------------------------------------------------------------
  // Independent abstract golden model
  //--------------------------------------------------------------------------
  bit ref_initial_fill;
  bit ref_write_active;
  bit ref_read_active;
  bit ref_write_group;
  bit ref_read_group;
  bit ref_read_pending;

  int unsigned ref_wr_addr;
  int unsigned ref_rd_addr;

  bit ref_read_valid_pipe [0:TB_BRAM_READ_LATENCY-1];
  bit ref_last_read_pipe  [0:TB_BRAM_READ_LATENCY-1];

  //--------------------------------------------------------------------------
  // Expected combinational values from the abstract model
  //--------------------------------------------------------------------------
  logic [TB_NUM_OUTPUT_BUFFERS-1:0] exp_wr_mask;
  logic [TB_NUM_OUTPUT_BUFFERS-1:0] exp_rd_mask;
  logic                             exp_wr_request;
  logic                             exp_rd_request;
  logic                             exp_out_valid;

  //--------------------------------------------------------------------------
  // Test status / coverage
  //--------------------------------------------------------------------------
  int errors;
  int checks;

  bit initial_fill_covered;
  bit write_gap_covered;
  bit parallel_rw_covered;
  bit write_finishes_first_covered;
  bit read_finishes_first_covered;
  bit simultaneous_completion_covered;
  bit read_drain_covered;
  bit group0_write_covered;
  bit group1_write_covered;
  bit group0_read_covered;
  bit group1_read_covered;
  bit out_valid_latency_covered;
  bit async_reset_covered;

  bit state_seen [0:6];


  //--------------------------------------------------------------------------
  // Clock
  //--------------------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;


  //--------------------------------------------------------------------------
  // Synchronization task
  //--------------------------------------------------------------------------
  task automatic sync();
    @(posedge clk);
    #1ps;
  endtask


  //--------------------------------------------------------------------------
  // DUT
  //--------------------------------------------------------------------------
  output_buffer_controller #(
      .OUTPUT_LENGTH      (TB_OUTPUT_LENGTH),
      .ADDR_WIDTH         (TB_ADDR_WIDTH),
      .NUM_OUTPUT_BUFFERS (TB_NUM_OUTPUT_BUFFERS),
      .PARALLEL_OUTPUTS   (TB_PARALLEL_OUTPUTS),
      .BRAM_READ_LATENCY  (TB_BRAM_READ_LATENCY)
  ) dut (
      .clk            (clk),
      .resetb         (resetb),
      .conv_valid     (conv_valid),
      .wr_addr        (wr_addr),
      .rd_addr        (rd_addr),
      .bram_wr_en     (bram_wr_en),
      .bram_rd_en     (bram_rd_en),
      .read_group_sel (read_group_sel),
      .out_valid      (out_valid)
  );


  //--------------------------------------------------------------------------
  // Expected request/mask generation
  //
  // These equations use only the abstract group model and external conv_valid;
  // they do not use DUT control signals.
  //--------------------------------------------------------------------------
  always_comb begin
    exp_wr_request = ref_write_active && conv_valid;
    exp_rd_request = ref_read_active && ~ref_read_pending;

    exp_wr_mask = ZERO_MASK;
    exp_rd_mask = ZERO_MASK;

    if (exp_wr_request)
      exp_wr_mask = ref_write_group ? GROUP1_MASK : GROUP0_MASK;

    if (exp_rd_request)
      exp_rd_mask = ref_read_group ? GROUP1_MASK : GROUP0_MASK;

    exp_out_valid = ref_read_valid_pipe[TB_BRAM_READ_LATENCY-1];
  end


  //--------------------------------------------------------------------------
  // Independent transaction-level golden model
  //
  // The model tracks abstract group roles and transaction counts. It does not
  // reproduce the seven-state FSM or instantiate counter logic.
  //--------------------------------------------------------------------------
  integer p;
  always @(posedge clk or negedge resetb) begin : golden_model
    bit write_complete_now;
    bit read_complete_now;
    bit last_read_request_now;
    bit next_write_active;
    bit next_read_active;
    bit next_read_pending;
    bit next_initial_fill;
    bit next_write_group;
    bit next_read_group;
    int unsigned next_wr_addr;
    int unsigned next_rd_addr;

    if (~resetb) begin
      ref_initial_fill  <= 1'b1;
      ref_write_active  <= 1'b1;
      ref_read_active   <= 1'b0;
      ref_write_group   <= 1'b0;
      ref_read_group    <= 1'b0;
      ref_read_pending  <= 1'b0;
      ref_wr_addr       <= 0;
      ref_rd_addr       <= 0;

      for (p = 0; p < TB_BRAM_READ_LATENCY; p = p + 1) begin
        ref_read_valid_pipe[p] <= 1'b0;
        ref_last_read_pipe[p]  <= 1'b0;
      end
    end
    else begin
      // Completion events sampled for this edge from the abstract pre-edge
      // transaction state.
      write_complete_now =
          ref_write_active &&
          conv_valid &&
          (ref_wr_addr == TB_OUTPUT_LENGTH-1);

      read_complete_now =
          ref_last_read_pipe[TB_BRAM_READ_LATENCY-1];

      last_read_request_now =
          ref_read_active &&
          ~ref_read_pending &&
          (ref_rd_addr == TB_OUTPUT_LENGTH-1);

      // Independent BRAM-latency history.
      ref_read_valid_pipe[0] <=
          ref_read_active && ~ref_read_pending;
      ref_last_read_pipe[0] <= last_read_request_now;

      for (p = 1; p < TB_BRAM_READ_LATENCY; p = p + 1) begin
        ref_read_valid_pipe[p] <= ref_read_valid_pipe[p-1];
        ref_last_read_pipe[p]  <= ref_last_read_pipe[p-1];
      end

      // Start from current abstract state and apply transactions completed on
      // this edge.
      next_initial_fill = ref_initial_fill;
      next_write_active = ref_write_active;
      next_read_active  = ref_read_active;
      next_write_group  = ref_write_group;
      next_read_group   = ref_read_group;
      next_read_pending = ref_read_pending;
      next_wr_addr      = ref_wr_addr;
      next_rd_addr      = ref_rd_addr;

      // Accepted write transaction.
      if (ref_write_active && conv_valid) begin
        if (write_complete_now)
          next_wr_addr = 0;
        else
          next_wr_addr = ref_wr_addr + 1;
      end

      // Issued read transaction.
      if (ref_read_active && ~ref_read_pending) begin
        if (last_read_request_now) begin
          next_rd_addr      = 0;
          next_read_pending = 1'b1;
        end
        else
          next_rd_addr = ref_rd_addr + 1;
      end

      // The active writer becomes inactive as soon as its group is full.
      if (write_complete_now)
        next_write_active = 1'b0;

      // The active reader becomes inactive only after its final request has
      // propagated through the complete BRAM read latency.
      if (read_complete_now) begin
        next_read_active  = 1'b0;
        next_read_pending = 1'b0;
      end

      // Initial fill has a unique startup rule: once group 0 is full, group 1
      // becomes the writer and group 0 becomes the reader.
      if (ref_initial_fill && write_complete_now) begin
        next_initial_fill = 1'b0;
        next_write_active = 1'b1;
        next_read_active  = 1'b1;
        next_write_group  = 1'b1;
        next_read_group   = 1'b0;
        next_read_pending = 1'b0;
        next_wr_addr      = 0;
        next_rd_addr      = 0;
      end
      // Normal ping-pong exchange occurs only when the current writer is full
      // and the current reader has completely drained.
      else if (~ref_initial_fill &&
               ~next_write_active &&
               ~next_read_active) begin
        next_write_active = 1'b1;
        next_read_active  = 1'b1;
        next_write_group  = ref_read_group;
        next_read_group   = ref_write_group;
        next_read_pending = 1'b0;
        next_wr_addr      = 0;
        next_rd_addr      = 0;
      end

      ref_initial_fill <= next_initial_fill;
      ref_write_active <= next_write_active;
      ref_read_active  <= next_read_active;
      ref_write_group  <= next_write_group;
      ref_read_group   <= next_read_group;
      ref_read_pending <= next_read_pending;
      ref_wr_addr      <= next_wr_addr;
      ref_rd_addr      <= next_rd_addr;
    end
  end


  //--------------------------------------------------------------------------
  // Automatic checker
  //--------------------------------------------------------------------------
  always @(negedge clk) begin
    if (resetb) begin
      checks = checks + 1;

      if (wr_addr !== ref_wr_addr[TB_ADDR_WIDTH-1:0]) begin
        $error("wr_addr mismatch: DUT=%0d GOLD=%0d", wr_addr, ref_wr_addr);
        errors = errors + 1;
      end

      if (rd_addr !== ref_rd_addr[TB_ADDR_WIDTH-1:0]) begin
        $error("rd_addr mismatch: DUT=%0d GOLD=%0d", rd_addr, ref_rd_addr);
        errors = errors + 1;
      end

      if (bram_wr_en !== exp_wr_mask) begin
        $error("bram_wr_en mismatch: DUT=%b GOLD=%b", bram_wr_en, exp_wr_mask);
        errors = errors + 1;
      end

      if (bram_rd_en !== exp_rd_mask) begin
        $error("bram_rd_en mismatch: DUT=%b GOLD=%b", bram_rd_en, exp_rd_mask);
        errors = errors + 1;
      end

      if (read_group_sel !== ref_read_group) begin
        $error("read_group_sel mismatch: DUT=%0b GOLD=%0b",
               read_group_sel, ref_read_group);
        errors = errors + 1;
      end

      if (out_valid !== exp_out_valid) begin
        $error("out_valid mismatch: DUT=%0b GOLD=%0b",
               out_valid, exp_out_valid);
        errors = errors + 1;
      end

      // The two physical groups must never be written and read simultaneously.
      if ((bram_wr_en & bram_rd_en) != ZERO_MASK) begin
        $error("Same physical output BRAM enabled for read and write: wr=%b rd=%b",
               bram_wr_en, bram_rd_en);
        errors = errors + 1;
      end

      // No data may be written while the abstract writer is blocked.
      if (~ref_write_active && (bram_wr_en != ZERO_MASK)) begin
        $error("Write enable asserted while abstract writer is blocked");
        errors = errors + 1;
      end
    end
  end


  //--------------------------------------------------------------------------
  // Coverage observation
  //--------------------------------------------------------------------------
  always @(negedge clk) begin
    if (resetb) begin
      if (dut_state <= 3'd6)
        state_seen[dut_state] = 1'b1;

      if (bram_wr_en == GROUP0_MASK)
        group0_write_covered = 1'b1;
      if (bram_wr_en == GROUP1_MASK)
        group1_write_covered = 1'b1;
      if (bram_rd_en == GROUP0_MASK)
        group0_read_covered = 1'b1;
      if (bram_rd_en == GROUP1_MASK)
        group1_read_covered = 1'b1;

      if ((bram_wr_en != ZERO_MASK) && (bram_rd_en != ZERO_MASK))
        parallel_rw_covered = 1'b1;

      if (dut_state == ST_WRITE1_ONLY || dut_state == ST_WRITE0_ONLY)
        read_finishes_first_covered = 1'b1;

      if (dut_state == ST_WAIT_READ0 || dut_state == ST_WAIT_READ1)
        write_finishes_first_covered = 1'b1;

      if (dut_read_pending && ~dut_rd_valid && (bram_rd_en == ZERO_MASK))
        read_drain_covered = 1'b1;

      if (dut_write_done && dut_read_done)
        simultaneous_completion_covered = 1'b1;

      if (out_valid == exp_out_valid && out_valid)
        out_valid_latency_covered = 1'b1;
    end
  end


  //--------------------------------------------------------------------------
  // Stimulus helper: change conv_valid only after sync()
  //--------------------------------------------------------------------------
  task automatic set_conv_valid(input logic value);
    begin
      sync();
      conv_valid = value;
      #1ps;
    end
  endtask


  //--------------------------------------------------------------------------
  // Stimulus helper: keep current conv_valid for a number of active edges.
  //--------------------------------------------------------------------------
  task automatic wait_cycles(input int unsigned cycles);
    int unsigned c;
    begin
      for (c = 0; c < cycles; c = c + 1)
        sync();
    end
  endtask


  //--------------------------------------------------------------------------
  // Stimulus helper: wait until the independent model reaches one parallel
  // ping-pong phase with the requested write/read groups.
  //--------------------------------------------------------------------------
  task automatic wait_for_ref_parallel(
      input bit expected_write_group,
      input bit expected_read_group
  );
    begin
      while (!(~ref_initial_fill &&
               ref_write_active &&
               ref_read_active &&
               (ref_write_group == expected_write_group) &&
               (ref_read_group  == expected_read_group))) begin
        sync();
      end
    end
  endtask


  //--------------------------------------------------------------------------
  // Stimulus helper: issue a requested number of valid convolution results.
  //--------------------------------------------------------------------------
  task automatic send_valid_results(input int unsigned count);
    int unsigned c;
    begin
      set_conv_valid(1'b1);
      for (c = 1; c < count; c = c + 1)
        sync();
    end
  endtask


  //--------------------------------------------------------------------------
  // Main test sequence
  //--------------------------------------------------------------------------
  initial begin
    errors = 0;
    checks = 0;

    initial_fill_covered             = 1'b0;
    write_gap_covered                = 1'b0;
    parallel_rw_covered              = 1'b0;
    write_finishes_first_covered     = 1'b0;
    read_finishes_first_covered      = 1'b0;
    simultaneous_completion_covered  = 1'b0;
    read_drain_covered               = 1'b0;
    group0_write_covered             = 1'b0;
    group1_write_covered             = 1'b0;
    group0_read_covered              = 1'b0;
    group1_read_covered              = 1'b0;
    out_valid_latency_covered        = 1'b0;
    async_reset_covered              = 1'b0;

    for (int s = 0; s < 7; s = s + 1)
      state_seen[s] = 1'b0;

    //-----------------------------------------------------------------------
    // TEST 1: asynchronous reset and initial state
    //-----------------------------------------------------------------------
    #2ns;
    resetb = 1'b0;
    #1ns;

    if ((wr_addr !== '0) ||
        (rd_addr !== '0) ||
        (bram_wr_en !== ZERO_MASK) ||
        (bram_rd_en !== ZERO_MASK) ||
        (out_valid !== 1'b0)) begin
      $error("Asynchronous reset did not clear controller outputs/state");
      errors = errors + 1;
    end

    async_reset_covered = 1'b1;

    // Reset deassertion is synchronous by testbench convention.
    sync();
    resetb = 1'b1;
    #1ps;

    //-----------------------------------------------------------------------
    // TEST 2: initial fill of group 0, including a conv_valid gap
    //-----------------------------------------------------------------------
    initial_fill_covered = 1'b1;

    set_conv_valid(1'b1);  // first accepted output
    set_conv_valid(1'b0);  // intentional gap: write address must hold
    wait_cycles(2);
    write_gap_covered = 1'b1;

    // Complete the remaining initial group-0 writes.
    send_valid_results(TB_OUTPUT_LENGTH - 1);

    // Stop driving new convolution outputs after group 0 becomes full.
    set_conv_valid(1'b0);

    //-----------------------------------------------------------------------
    // TEST 3: write finishes first -> WAIT_READ0
    //
    // Group 1 and group 0 start together. Continuous conv_valid fills group 1
    // before the delayed final read of group 0 completes.
    //-----------------------------------------------------------------------
    wait_for_ref_parallel(1'b1, 1'b0);
    send_valid_results(TB_OUTPUT_LENGTH);
    set_conv_valid(1'b0);
    wait_cycles(TB_BRAM_READ_LATENCY + 2);

    //-----------------------------------------------------------------------
    // TEST 4: read finishes first -> WRITE0_ONLY
    //
    // Allow only one write into group 0, then pause convolution results long
    // enough for group 1 to finish reading. The partial write address must be
    // retained until valid convolution results resume.
    //-----------------------------------------------------------------------
    wait_for_ref_parallel(1'b0, 1'b1);
    send_valid_results(1);
    set_conv_valid(1'b0);
    wait_cycles(TB_OUTPUT_LENGTH + TB_BRAM_READ_LATENCY + 1);
    send_valid_results(TB_OUTPUT_LENGTH - 1);
    set_conv_valid(1'b0);

    //-----------------------------------------------------------------------
    // TEST 5: simultaneous write/read completion
    //
    // Start writing group 1 late enough that its final write aligns with the
    // delayed completion of the final group-0 read.
    //-----------------------------------------------------------------------
    wait_for_ref_parallel(1'b1, 1'b0);
    wait_cycles(TB_BRAM_READ_LATENCY - 1);
    send_valid_results(TB_OUTPUT_LENGTH);
    set_conv_valid(1'b0);

    //-----------------------------------------------------------------------
    // TEST 6: opposite write-finishes-first direction -> WAIT_READ1
    //-----------------------------------------------------------------------
    wait_for_ref_parallel(1'b0, 1'b1);
    send_valid_results(TB_OUTPUT_LENGTH);
    set_conv_valid(1'b0);
    wait_cycles(TB_BRAM_READ_LATENCY + 2);

    //-----------------------------------------------------------------------
    // TEST 7: opposite read-finishes-first direction -> WRITE1_ONLY
    //-----------------------------------------------------------------------
    wait_for_ref_parallel(1'b1, 1'b0);
    send_valid_results(1);
    set_conv_valid(1'b0);
    wait_cycles(TB_OUTPUT_LENGTH + TB_BRAM_READ_LATENCY + 1);
    send_valid_results(TB_OUTPUT_LENGTH - 1);
    set_conv_valid(1'b0);
    wait_cycles(2);

    //-----------------------------------------------------------------------
    // TEST 8: asynchronous reset during active ping-pong operation
    //-----------------------------------------------------------------------
    set_conv_valid(1'b1);
    wait_cycles(2);

    #(CLK_PERIOD/4);
    resetb = 1'b0;
    #1ps;

    if ((wr_addr !== '0) ||
        (rd_addr !== '0) ||
        (out_valid !== 1'b0) ||
        (dut_state !== ST_FILL_GROUP0)) begin
      $error("Runtime asynchronous reset failed");
      errors = errors + 1;
    end

    conv_valid = 1'b0;

    sync();
    resetb = 1'b1;
    #1ps;

    wait_cycles(2);

    //-----------------------------------------------------------------------
    // Coverage checks
    //-----------------------------------------------------------------------
    for (int s = 0; s < 7; s = s + 1) begin
      if (!state_seen[s]) begin
        $error("FSM state %0d was not observed during controller test", s);
        errors = errors + 1;
      end
    end

    if (!initial_fill_covered) begin
      $error("Initial-fill coverage missing");
      errors = errors + 1;
    end

    if (!write_gap_covered) begin
      $error("Write-gap coverage missing");
      errors = errors + 1;
    end

    if (!parallel_rw_covered) begin
      $error("Parallel read/write coverage missing");
      errors = errors + 1;
    end

    if (!write_finishes_first_covered) begin
      $error("Write-finishes-first / WAIT_READ coverage missing");
      errors = errors + 1;
    end

    if (!read_finishes_first_covered) begin
      $error("Read-finishes-first / WRITE_ONLY coverage missing");
      errors = errors + 1;
    end

    if (!simultaneous_completion_covered) begin
      $error("Simultaneous write/read completion coverage missing");
      errors = errors + 1;
    end

    if (!read_drain_covered) begin
      $error("Final-read drain coverage missing");
      errors = errors + 1;
    end

    if (!group0_write_covered || !group1_write_covered ||
        !group0_read_covered  || !group1_read_covered) begin
      $error("Both output-buffer groups were not fully exercised for read/write");
      errors = errors + 1;
    end

    if (!out_valid_latency_covered) begin
      $error("out_valid BRAM-latency coverage missing");
      errors = errors + 1;
    end

    if (!async_reset_covered) begin
      $error("Asynchronous reset coverage missing");
      errors = errors + 1;
    end

    //-----------------------------------------------------------------------
    // Final result
    //-----------------------------------------------------------------------
    if (errors == 0)
      $display("PASS: tb_output_buffer_controller completed with %0d automatic checks.", checks);
    else
      $fatal(1, "FAIL: tb_output_buffer_controller completed with %0d errors.", errors);

    $finish;
  end

endmodule
