`timescale 1ns/1ps

/*==============================================================================
  Testbench: tb_output_buffer_fsm
  Purpose:
    Directed functional verification of output_buffer_fsm.

    The test covers the complete two-group ping-pong behavior:
      1) Initial asynchronous reset and initial fill of group 0
      2) Parallel write-group-1 / read-group-0 operation
      3) Read-finishes-first path through ST_WRITE1_ONLY
      4) Write-finishes-first path through ST_WAIT_READ0
      5) Parallel write-group-0 / read-group-1 operation
      6) Read-finishes-first path through ST_WRITE0_ONLY
      7) Write-finishes-first path through ST_WAIT_READ1
      8) Simultaneous write/read completion in both ping-pong directions
      9) Asynchronous reset during active ping-pong operation

  Independent golden-model methodology:
    - The golden model does NOT reproduce the DUT state-transition case tree.
    - It models the abstract ping-pong behavior using:
        * current write group
        * current read group
        * whether writing is active
        * whether reading is active
        * whether the system is still performing the initial group-0 fill
    - A completion event disables the corresponding abstract activity.
    - Once both the current write and read operations have completed, the two
      physical groups exchange roles and both activities restart.
    - The expected FSM state is derived only from this abstract model.

  Checks covered:
    - current state and combinational next_state
    - en_write and en_read
    - write_group_sel and read_group_sel
    - all 18 defined FSM transitions
    - read-finishes-first behavior
    - write-finishes-first behavior
    - simultaneous completion behavior
    - asynchronous reset behavior

  Timing rule:
    - sync() is a dedicated synchronization task.
    - Normal stimulus changes are made only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges to verify
      asynchronous reset behavior.
==============================================================================*/

module tb_output_buffer_fsm;

  //--------------------------------------------------------------------------
  // State encoding -- used only for state observation and readable reporting
  //--------------------------------------------------------------------------
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
  logic write_done = 1'b0;
  logic read_done  = 1'b0;

  //--------------------------------------------------------------------------
  // DUT outputs
  //--------------------------------------------------------------------------
  logic en_write;
  logic en_read;
  logic write_group_sel;
  logic read_group_sel;

  //--------------------------------------------------------------------------
  // Internal DUT observation
  //--------------------------------------------------------------------------
  logic [2:0] state;
  logic [2:0] next_state;

  //--------------------------------------------------------------------------
  // Independent abstract golden model
  //--------------------------------------------------------------------------
  bit ref_initial_fill;
  bit ref_write_active;
  bit ref_read_active;
  bit ref_write_group;
  bit ref_read_group;

  //--------------------------------------------------------------------------
  // Error counter and manual coverage
  //--------------------------------------------------------------------------
  int errors;

  bit transition_cov [0:6][0:6];
  bit async_reset_seen;
  bit read_finishes_first_seen;
  bit write_finishes_first_seen;
  bit simultaneous_completion_seen;

  //--------------------------------------------------------------------------
  // Clock: 10 ns period
  //--------------------------------------------------------------------------
  always #5 clk = ~clk;

  //--------------------------------------------------------------------------
  // Posedge synchronization + tiny settle time
  //--------------------------------------------------------------------------
  task automatic sync();
    @(posedge clk);
    #1ps;
  endtask

  //--------------------------------------------------------------------------
  // DUT
  //--------------------------------------------------------------------------
  output_buffer_fsm dut (
      .clk             (clk),
      .resetb          (resetb),
      .write_done      (write_done),
      .read_done       (read_done),
      .en_write        (en_write),
      .en_read         (en_read),
      .write_group_sel (write_group_sel),
      .read_group_sel  (read_group_sel)
  );

  // Internal DUT signals are observed hierarchically for verification only.
  assign state      = dut.state;
  assign next_state = dut.next_state;

  //--------------------------------------------------------------------------
  // State-name helper
  //--------------------------------------------------------------------------
  function automatic string state_name(input logic [2:0] s);
    case (s)
      ST_FILL_GROUP0:  return "ST_FILL_GROUP0";
      ST_WRITE1_READ0: return "ST_WRITE1_READ0";
      ST_WRITE1_ONLY:  return "ST_WRITE1_ONLY";
      ST_WAIT_READ0:   return "ST_WAIT_READ0";
      ST_WRITE0_READ1: return "ST_WRITE0_READ1";
      ST_WRITE0_ONLY:  return "ST_WRITE0_ONLY";
      ST_WAIT_READ1:   return "ST_WAIT_READ1";
      default:         return "UNKNOWN_STATE";
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Coverage-state index helper
  //--------------------------------------------------------------------------
  function automatic int cov_state_idx(input logic [2:0] s);
    case (s)
      ST_FILL_GROUP0:  return 0;
      ST_WRITE1_READ0: return 1;
      ST_WRITE1_ONLY:  return 2;
      ST_WAIT_READ0:   return 3;
      ST_WRITE0_READ1: return 4;
      ST_WRITE0_ONLY:  return 5;
      ST_WAIT_READ1:   return 6;
      default:         return -1;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Convert the abstract golden-model configuration to one expected FSM state.
  // This function describes meaning, not DUT transition logic.
  //--------------------------------------------------------------------------
  function automatic logic [2:0] golden_state(
      input bit initial_fill,
      input bit write_active,
      input bit read_active,
      input bit write_group,
      input bit read_group
  );
    if (initial_fill)
      return ST_FILL_GROUP0;

    if (write_active && read_active) begin
      if (write_group && ~read_group)
        return ST_WRITE1_READ0;
      else if (~write_group && read_group)
        return ST_WRITE0_READ1;
    end

    if (write_active && ~read_active) begin
      if (write_group)
        return ST_WRITE1_ONLY;
      else
        return ST_WRITE0_ONLY;
    end

    if (~write_active && read_active) begin
      if (~read_group)
        return ST_WAIT_READ0;
      else
        return ST_WAIT_READ1;
    end

    return 3'bxxx;
  endfunction

  //--------------------------------------------------------------------------
  // Independent golden-model step.
  // Packed order:
  // {initial_fill, write_active, read_active, write_group, read_group}
  //--------------------------------------------------------------------------
  function automatic logic [4:0] golden_next_model(
      input bit initial_fill_i,
      input bit write_active_i,
      input bit read_active_i,
      input bit write_group_i,
      input bit read_group_i,
      input bit write_done_i,
      input bit read_done_i
  );
    bit initial_fill_n;
    bit write_active_n;
    bit read_active_n;
    bit write_group_n;
    bit read_group_n;

    initial_fill_n = initial_fill_i;
    write_active_n = write_active_i;
    read_active_n  = read_active_i;
    write_group_n  = write_group_i;
    read_group_n   = read_group_i;

    // Initial phase: only group 0 is being filled.
    if (initial_fill_i) begin
      if (write_active_i && write_done_i) begin
        initial_fill_n = 1'b0;
        write_group_n  = 1'b1;
        read_group_n   = 1'b0;
        write_active_n = 1'b1;
        read_active_n  = 1'b1;
      end
    end

    // Normal ping-pong phase. Completion independently stops each side.
    // When both sides are complete, the two groups exchange roles.
    else begin
      if (write_active_i && write_done_i)
        write_active_n = 1'b0;

      if (read_active_i && read_done_i)
        read_active_n = 1'b0;

      if (~write_active_n && ~read_active_n) begin
        write_group_n  = read_group_i;
        read_group_n   = write_group_i;
        write_active_n = 1'b1;
        read_active_n  = 1'b1;
      end
    end

    return {initial_fill_n, write_active_n, read_active_n,
            write_group_n, read_group_n};
  endfunction

  //--------------------------------------------------------------------------
  // Reset the abstract golden model
  //--------------------------------------------------------------------------
  task automatic golden_reset();
    ref_initial_fill = 1'b1;
    ref_write_active = 1'b1;
    ref_read_active  = 1'b0;
    ref_write_group  = 1'b0;
    ref_read_group   = 1'b0;
  endtask

  //--------------------------------------------------------------------------
  // Advance the abstract golden model by one active clock edge.
  // No clock synchronization is performed inside this task.
  //--------------------------------------------------------------------------
  task automatic golden_advance();
    logic [4:0] next_model;

    next_model = golden_next_model(
        ref_initial_fill,
        ref_write_active,
        ref_read_active,
        ref_write_group,
        ref_read_group,
        write_done,
        read_done
    );

    {ref_initial_fill,
     ref_write_active,
     ref_read_active,
     ref_write_group,
     ref_read_group} = next_model;
  endtask

  //--------------------------------------------------------------------------
  // Record one expected FSM transition
  //--------------------------------------------------------------------------
  task automatic record_transition(
      input logic [2:0] from_state,
      input logic [2:0] to_state
  );
    int from_idx;
    int to_idx;

    from_idx = cov_state_idx(from_state);
    to_idx   = cov_state_idx(to_state);

    if ((from_idx >= 0) && (to_idx >= 0))
      transition_cov[from_idx][to_idx] = 1'b1;
  endtask

  //--------------------------------------------------------------------------
  // Check current DUT state, next_state, and outputs against the independent
  // abstract golden model.
  //--------------------------------------------------------------------------
  task automatic check_case(input string label);
    logic [2:0] exp_state;
    logic [2:0] exp_next_state;
    logic [4:0] next_model;
    logic [3:0] got_outputs;
    logic [3:0] exp_outputs;
    bit failed;

    failed = 1'b0;

    exp_state = golden_state(
        ref_initial_fill,
        ref_write_active,
        ref_read_active,
        ref_write_group,
        ref_read_group
    );

    next_model = golden_next_model(
        ref_initial_fill,
        ref_write_active,
        ref_read_active,
        ref_write_group,
        ref_read_group,
        write_done,
        read_done
    );

    exp_next_state = golden_state(
        next_model[4], next_model[3], next_model[2],
        next_model[1], next_model[0]
    );

    // The four DUT outputs directly describe the abstract current operation.
    got_outputs = {en_write, en_read, write_group_sel, read_group_sel};
    exp_outputs = {ref_write_active, ref_read_active,
                   ref_write_group, ref_read_group};

    if (state !== exp_state) begin
      $error("[%0t] FAIL %s state: got=%s(%0d) exp=%s(%0d)",
             $time, label,
             state_name(state), state,
             state_name(exp_state), exp_state);
      errors = errors + 1;
      failed = 1'b1;
    end

    if (next_state !== exp_next_state) begin
      $error("[%0t] FAIL %s next_state: got=%s(%0d) exp=%s(%0d)",
             $time, label,
             state_name(next_state), next_state,
             state_name(exp_next_state), exp_next_state);
      errors = errors + 1;
      failed = 1'b1;
    end

    if (got_outputs !== exp_outputs) begin
      $error("[%0t] FAIL %s outputs: got=%b exp=%b",
             $time, label, got_outputs, exp_outputs);
      errors = errors + 1;
      failed = 1'b1;
    end

    record_transition(exp_state, exp_next_state);

    if (!failed) begin
      $display("[%0t] PASS %-34s state=%-18s wr_done=%0b rd_done=%0b en_wr=%0b en_rd=%0b wr_grp=%0b rd_grp=%0b next=%s",
               $time, label, state_name(state), write_done, read_done,
               en_write, en_read, write_group_sel, read_group_sel,
               state_name(next_state));
    end
  endtask

  //--------------------------------------------------------------------------
  // Verify state immediately after a clock edge before changing stimulus.
  //--------------------------------------------------------------------------
  task automatic expect_current_state(input string label);
    logic [2:0] exp_state;

    exp_state = golden_state(
        ref_initial_fill,
        ref_write_active,
        ref_read_active,
        ref_write_group,
        ref_read_group
    );

    if (state !== exp_state) begin
      $error("[%0t] FAIL %s state: got=%s exp=%s",
             $time, label, state_name(state), state_name(exp_state));
      errors = errors + 1;
    end
  endtask

  //--------------------------------------------------------------------------
  // Manual transition coverage summary
  //--------------------------------------------------------------------------
  task automatic print_coverage_summary();
    int hit;
    int total;

    hit   = 0;
    total = 18;

    $display("\n================ Coverage Summary ================");

    $write("FILL_GROUP0 -> FILL_GROUP0   : %0d\n", transition_cov[0][0]); hit += transition_cov[0][0];
    $write("FILL_GROUP0 -> WRITE1_READ0  : %0d\n", transition_cov[0][1]); hit += transition_cov[0][1];

    $write("WRITE1_READ0 -> WRITE1_READ0 : %0d\n", transition_cov[1][1]); hit += transition_cov[1][1];
    $write("WRITE1_READ0 -> WRITE1_ONLY  : %0d\n", transition_cov[1][2]); hit += transition_cov[1][2];
    $write("WRITE1_READ0 -> WAIT_READ0   : %0d\n", transition_cov[1][3]); hit += transition_cov[1][3];
    $write("WRITE1_READ0 -> WRITE0_READ1 : %0d\n", transition_cov[1][4]); hit += transition_cov[1][4];

    $write("WRITE1_ONLY -> WRITE1_ONLY   : %0d\n", transition_cov[2][2]); hit += transition_cov[2][2];
    $write("WRITE1_ONLY -> WRITE0_READ1  : %0d\n", transition_cov[2][4]); hit += transition_cov[2][4];

    $write("WAIT_READ0 -> WAIT_READ0     : %0d\n", transition_cov[3][3]); hit += transition_cov[3][3];
    $write("WAIT_READ0 -> WRITE0_READ1   : %0d\n", transition_cov[3][4]); hit += transition_cov[3][4];

    $write("WRITE0_READ1 -> WRITE0_READ1 : %0d\n", transition_cov[4][4]); hit += transition_cov[4][4];
    $write("WRITE0_READ1 -> WRITE0_ONLY  : %0d\n", transition_cov[4][5]); hit += transition_cov[4][5];
    $write("WRITE0_READ1 -> WAIT_READ1   : %0d\n", transition_cov[4][6]); hit += transition_cov[4][6];
    $write("WRITE0_READ1 -> WRITE1_READ0 : %0d\n", transition_cov[4][1]); hit += transition_cov[4][1];

    $write("WRITE0_ONLY -> WRITE0_ONLY   : %0d\n", transition_cov[5][5]); hit += transition_cov[5][5];
    $write("WRITE0_ONLY -> WRITE1_READ0  : %0d\n", transition_cov[5][1]); hit += transition_cov[5][1];

    $write("WAIT_READ1 -> WAIT_READ1     : %0d\n", transition_cov[6][6]); hit += transition_cov[6][6];
    $write("WAIT_READ1 -> WRITE1_READ0   : %0d\n", transition_cov[6][1]); hit += transition_cov[6][1];

    $display("--------------------------------------------------");
    $display("Defined FSM transitions:       %0d / %0d", hit, total);
    $display("Async reset checked:           %0d", async_reset_seen);
    $display("Read finishes first checked:   %0d", read_finishes_first_seen);
    $display("Write finishes first checked:  %0d", write_finishes_first_seen);
    $display("Simultaneous completion checked:%0d", simultaneous_completion_seen);
    $display("==================================================\n");

    if (hit != total) begin
      $error("Coverage failure: only %0d of %0d defined transitions were covered", hit, total);
      errors = errors + 1;
    end

    if (!async_reset_seen ||
        !read_finishes_first_seen ||
        !write_finishes_first_seen ||
        !simultaneous_completion_seen) begin
      $error("Coverage failure: one or more directed behavior categories were not exercised");
      errors = errors + 1;
    end
  endtask

  //--------------------------------------------------------------------------
  // Test sequence
  //--------------------------------------------------------------------------
  initial begin
    errors                       = 0;
    async_reset_seen             = 1'b0;
    read_finishes_first_seen     = 1'b0;
    write_finishes_first_seen    = 1'b0;
    simultaneous_completion_seen = 1'b0;

    golden_reset();

    $display("== tb_output_buffer_fsm ==");

    //======================================================================
    // Stage 0 -- Initial asynchronous reset
    //======================================================================
    resetb = 1'b0;
    #2.5ns;

    if ((state !== ST_FILL_GROUP0) ||
        ({en_write, en_read, write_group_sel, read_group_sel} !== 4'b1000)) begin
      $error("[%0t] FAIL async reset: state=%s outputs=%b",
             $time, state_name(state),
             {en_write, en_read, write_group_sel, read_group_sel});
      errors = errors + 1;
    end
    else begin
      $display("[%0t] PASS async reset => ST_FILL_GROUP0", $time);
      async_reset_seen = 1'b1;
    end

    // Synchronized reset release.
    sync();
    resetb = 1'b1;
    #1ps;

    check_case("RESET RELEASE / FILL HOLD");

    //======================================================================
    // Stage 1 -- Complete initial group-0 fill
    //======================================================================
    // Consume the FILL_GROUP0 self transition before changing stimulus.
    sync();
    golden_advance();
    expect_current_state("Initial fill hold result");

    write_done = 1'b1;
    #1ps;
    check_case("FILL_GROUP0 -> WRITE1_READ0");

    sync();
    golden_advance();
    expect_current_state("Enter WRITE1_READ0");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("WRITE1_READ0 hold");

    //======================================================================
    // Stage 2 -- Read finishes first: group 0 before group 1 fill
    //======================================================================
    sync();
    golden_advance();
    expect_current_state("WRITE1_READ0 hold result");

    read_done = 1'b1;
    #1ps;
    check_case("READ0 first -> WRITE1_ONLY");
    read_finishes_first_seen = 1'b1;

    sync();
    golden_advance();
    expect_current_state("Enter WRITE1_ONLY");

    read_done  = 1'b0;
    write_done = 1'b0;
    #1ps;
    check_case("WRITE1_ONLY hold");

    sync();
    golden_advance();
    expect_current_state("WRITE1_ONLY hold result");

    write_done = 1'b1;
    #1ps;
    check_case("WRITE1_ONLY -> WRITE0_READ1");

    sync();
    golden_advance();
    expect_current_state("Enter WRITE0_READ1");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("WRITE0_READ1 hold");

    //======================================================================
    // Stage 3 -- Write finishes first: group 0 before group 1 read
    //======================================================================
    sync();
    golden_advance();
    expect_current_state("WRITE0_READ1 hold result");

    write_done = 1'b1;
    #1ps;
    check_case("WRITE0 first -> WAIT_READ1");
    write_finishes_first_seen = 1'b1;

    sync();
    golden_advance();
    expect_current_state("Enter WAIT_READ1");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("WAIT_READ1 hold");

    sync();
    golden_advance();
    expect_current_state("WAIT_READ1 hold result");

    read_done = 1'b1;
    #1ps;
    check_case("WAIT_READ1 -> WRITE1_READ0");

    sync();
    golden_advance();
    expect_current_state("Return WRITE1_READ0");

    read_done  = 1'b0;
    write_done = 1'b1;
    #1ps;
    check_case("WRITE1 first -> WAIT_READ0");

    //======================================================================
    // Stage 4 -- Wait for read0 after write1 completed first
    //======================================================================
    sync();
    golden_advance();
    expect_current_state("Enter WAIT_READ0");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("WAIT_READ0 hold");

    sync();
    golden_advance();
    expect_current_state("WAIT_READ0 hold result");

    read_done = 1'b1;
    #1ps;
    check_case("WAIT_READ0 -> WRITE0_READ1");

    sync();
    golden_advance();
    expect_current_state("Return WRITE0_READ1");

    read_done  = 1'b0;
    write_done = 1'b0;
    #1ps;
    check_case("WRITE0_READ1 second hold");

    //======================================================================
    // Stage 5 -- Read1 finishes first: ST_WRITE0_ONLY
    //======================================================================
    sync();
    golden_advance();
    expect_current_state("WRITE0_READ1 second hold result");

    read_done = 1'b1;
    #1ps;
    check_case("READ1 first -> WRITE0_ONLY");

    sync();
    golden_advance();
    expect_current_state("Enter WRITE0_ONLY");

    read_done  = 1'b0;
    write_done = 1'b0;
    #1ps;
    check_case("WRITE0_ONLY hold");

    sync();
    golden_advance();
    expect_current_state("WRITE0_ONLY hold result");

    write_done = 1'b1;
    #1ps;
    check_case("WRITE0_ONLY -> WRITE1_READ0");

    //======================================================================
    // Stage 6 -- Simultaneous completion in both directions
    //======================================================================
    sync();
    golden_advance();
    expect_current_state("Enter WRITE1_READ0 before simultaneous completion");

    write_done = 1'b1;
    read_done  = 1'b1;
    #1ps;
    check_case("WRITE1_READ0 simultaneous done");
    simultaneous_completion_seen = 1'b1;

    sync();
    golden_advance();
    expect_current_state("Enter WRITE0_READ1 after simultaneous completion");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("WRITE0_READ1 before second simultaneous done");

    sync();
    golden_advance();
    expect_current_state("WRITE0_READ1 stable before second simultaneous done");

    write_done = 1'b1;
    read_done  = 1'b1;
    #1ps;
    check_case("WRITE0_READ1 simultaneous done");

    sync();
    golden_advance();
    expect_current_state("Return WRITE1_READ0 after simultaneous completion");

    write_done = 1'b0;
    read_done  = 1'b0;
    #1ps;
    check_case("FINAL ACTIVE PING-PONG BASELINE");

    //======================================================================
    // Stage 7 -- Asynchronous reset during active operation
    //======================================================================
    #2.5ns;
    resetb = 1'b0;
    golden_reset();
    #1ps;

    if ((state !== ST_FILL_GROUP0) ||
        ({en_write, en_read, write_group_sel, read_group_sel} !== 4'b1000)) begin
      $error("[%0t] FAIL runtime async reset: state=%s outputs=%b",
             $time, state_name(state),
             {en_write, en_read, write_group_sel, read_group_sel});
      errors = errors + 1;
    end
    else begin
      $display("[%0t] PASS runtime async reset => ST_FILL_GROUP0", $time);
    end

    sync();
    resetb = 1'b1;
    #1ps;
    check_case("RUNTIME RESET RELEASE");

    //--------------------------------------------------------------------
    // Summary
    //--------------------------------------------------------------------
    print_coverage_summary();

    if (errors == 0)
      $display("== TEST PASSED: 0 errors ==");
    else
      $display("== TEST FAILED: %0d error(s) ==", errors);

    #10ns;
    $stop;
  end

endmodule
