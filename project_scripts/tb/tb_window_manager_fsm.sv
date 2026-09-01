`timescale 1ns/1ps

/*==============================================================================
  Testbench: tb_window_manager_fsm
  Purpose:
    Directed functional testbench for the updated window_manager_fsm.

    The test follows the FSM through the updated circular-row-buffer behavior:
      1) Initial asynchronous reset assertion and synchronized release
      2) Initial accumulation of INIT_ROWS real rows before processing starts
      3) Normal parallel write/read operation
      4) ST_WAIT_WRITE when processing finishes before the next logical row is
         available
      5) ST_WAIT_PROCESS when writing reaches the protected buffer margin
      6) Normal next-window advance through ST_ADVANCE_WINDOW
      7) End-of-frame row-counter clear and accumulation of rows from the next
         frame while the previous frame is still being processed
      8) Final-window completion through ST_FRAME_SWITCH
      9) Both frame-switch cases:
           - next frame already has INIT_ROWS rows -> ST_RUN_BOTH
           - next frame has fewer than INIT_ROWS rows -> ST_INIT_FILL

  Checks covered:
    - state and next_state through hierarchical DUT observation
    - rows_loaded counter behavior and saturation at INIT_ROWS
    - rows_done pulse on the INIT_ROWS-th completed real row
    - synchronous rows_loaded clear by frame_done
    - en_write_row
    - en_process_window
    - advance_window
    - frame_switch
    - all defined FSM transition paths
    - transition priority when process_done is asserted together with
      write_blocked

  Timing rule:
    - sync() is used before every runtime stimulus change.
    - Reset assertion is intentionally asynchronous.
    - Reset release is performed immediately after sync().
==============================================================================*/
module tb_window_manager_fsm;

  //--------------------------------------------------------------------------
  // Parameters
  //--------------------------------------------------------------------------
  localparam int ROW_CNT_W = 3;
  localparam int INIT_ROWS = 5;

  //--------------------------------------------------------------------------
  // State encoding -- must match the DUT
  //--------------------------------------------------------------------------
  localparam logic [2:0]
      ST_INIT_FILL      = 3'd0,
      ST_RUN_BOTH       = 3'd1,
      ST_WAIT_WRITE     = 3'd2,
      ST_WAIT_PROCESS   = 3'd3,
      ST_ADVANCE_WINDOW = 3'd4,
      ST_FRAME_SWITCH   = 3'd5;

  //--------------------------------------------------------------------------
  // Clock / Reset / Stimulus
  //--------------------------------------------------------------------------
  logic clk                = 1'b0;
  logic resetb             = 1'b1;
  logic row_write_done     = 1'b0;
  logic process_done       = 1'b0;
  logic frame_done         = 1'b0;
  logic next_row_ready     = 1'b0;
  logic write_blocked      = 1'b0;
  logic last_window        = 1'b0;

  //--------------------------------------------------------------------------
  // DUT outputs
  //--------------------------------------------------------------------------
  logic en_write_row;
  logic en_process_window;
  logic advance_window;
  logic frame_switch;

  //--------------------------------------------------------------------------
  // Internal DUT observation
  // These signals intentionally remain internal to the DUT interface.
  //--------------------------------------------------------------------------
  logic [ROW_CNT_W-1:0] rows_loaded;
  logic                 rows_done;
  logic [2:0]           state;
  logic [2:0]           next_state;

  //--------------------------------------------------------------------------
  // Error counter and manual transition coverage
  //--------------------------------------------------------------------------
  int errors;

  bit transition_cov [0:5][0:5];
  bit async_reset_seen;
  bit frame_done_clear_seen;
  bit rows_accumulated_while_processing_seen;

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
  window_manager_fsm #(
      .ROW_CNT_W (ROW_CNT_W),
      .INIT_ROWS (INIT_ROWS)
  ) dut (
      .clk               (clk),
      .resetb            (resetb),
      .row_write_done    (row_write_done),
      .process_done      (process_done),
      .frame_done        (frame_done),
      .next_row_ready    (next_row_ready),
      .write_blocked     (write_blocked),
      .last_window       (last_window),
      .en_write_row      (en_write_row),
      .en_process_window (en_process_window),
      .advance_window    (advance_window),
      .frame_switch      (frame_switch)
  );

  // Internal DUT signals are observed hierarchically for verification only.
  assign rows_loaded = dut.rows_loaded;
  assign rows_done   = dut.rows_done;
  assign state       = dut.state;
  assign next_state  = dut.next_state;

  //--------------------------------------------------------------------------
  // State-name helper
  //--------------------------------------------------------------------------
  function automatic string state_name(input logic [2:0] s);
    case (s)
      ST_INIT_FILL:      return "ST_INIT_FILL";
      ST_RUN_BOTH:       return "ST_RUN_BOTH";
      ST_WAIT_WRITE:     return "ST_WAIT_WRITE";
      ST_WAIT_PROCESS:   return "ST_WAIT_PROCESS";
      ST_ADVANCE_WINDOW: return "ST_ADVANCE_WINDOW";
      ST_FRAME_SWITCH:   return "ST_FRAME_SWITCH";
      default:           return "UNKNOWN_STATE";
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Coverage-state index helper
  //--------------------------------------------------------------------------
  function automatic int cov_state_idx(input logic [2:0] s);
    case (s)
      ST_INIT_FILL:      return 0;
      ST_RUN_BOTH:       return 1;
      ST_WAIT_WRITE:     return 2;
      ST_WAIT_PROCESS:   return 3;
      ST_ADVANCE_WINDOW: return 4;
      ST_FRAME_SWITCH:   return 5;
      default:           return -1;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Expected outputs for each state
  // Packed order:
  // {en_write_row, en_process_window, advance_window, frame_switch}
  //--------------------------------------------------------------------------
  function automatic logic [3:0] expected_outputs(
      input logic [2:0] s,
      input logic       blocked
  );
    case (s)
      ST_INIT_FILL:      return {~blocked, 1'b0, 1'b0, 1'b0};
      ST_RUN_BOTH:       return {~blocked, 1'b1, 1'b0, 1'b0};
      ST_WAIT_WRITE:     return {~blocked, 1'b0, 1'b0, 1'b0};
      ST_WAIT_PROCESS:   return 4'b0100;
      ST_ADVANCE_WINDOW: return {~blocked, 1'b0, 1'b1, 1'b0};
      ST_FRAME_SWITCH:   return {~blocked, 1'b0, 1'b0, 1'b1};
      default:           return 4'b0000;
    endcase
  endfunction

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

    if ((from_idx >= 0) & (to_idx >= 0))
      transition_cov[from_idx][to_idx] = 1'b1;
  endtask

  //--------------------------------------------------------------------------
  // Check the four state-controlled outputs
  //--------------------------------------------------------------------------
  task automatic expect_outputs(
      input  string      label,
      input  logic [2:0] exp_state,
      output bit         mismatch
  );
    logic [3:0] got;
    logic [3:0] exp;

    mismatch = 1'b0;
    got = {en_write_row, en_process_window, advance_window, frame_switch};
    exp = expected_outputs(exp_state, write_blocked);

    if (got !== exp) begin
      $error("[%0t] FAIL %s outputs: got=%b exp=%b",
             $time, label, got, exp);
      errors = errors + 1;
      mismatch = 1'b1;
    end
  endtask

  //--------------------------------------------------------------------------
  // Full check for one intended state/input coverage point
  //--------------------------------------------------------------------------
  task automatic check_case(
      input string                    label,
      input logic [2:0]               exp_state,
      input logic [2:0]               exp_next_state,
      input logic [ROW_CNT_W-1:0]     exp_rows_loaded,
      input logic                     exp_rows_done
  );
    bit failed;
    bit output_failed;

    failed = 1'b0;

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

    if (rows_loaded !== exp_rows_loaded) begin
      $error("[%0t] FAIL %s rows_loaded: got=%0d exp=%0d",
             $time, label, rows_loaded, exp_rows_loaded);
      errors = errors + 1;
      failed = 1'b1;
    end

    if (rows_done !== exp_rows_done) begin
      $error("[%0t] FAIL %s rows_done: got=%0b exp=%0b",
             $time, label, rows_done, exp_rows_done);
      errors = errors + 1;
      failed = 1'b1;
    end

    expect_outputs(label, exp_state, output_failed);
    if (output_failed)
      failed = 1'b1;

    record_transition(exp_state, exp_next_state);

    if (!failed) begin
      $display("[%0t] PASS %-34s state=%-18s wr_done=%0b proc_done=%0b frame_done=%0b next_ready=%0b blocked=%0b last=%0b rows=%0d next=%s",
               $time, label, state_name(state), row_write_done, process_done,
               frame_done, next_row_ready, write_blocked, last_window,
               rows_loaded, state_name(next_state));
    end
  endtask

  //--------------------------------------------------------------------------
  // Simple post-edge state/counter check.
  // Used before changing the next stimulus so counter effects are explicit.
  //--------------------------------------------------------------------------
  task automatic expect_state_rows(
      input string                    label,
      input logic [2:0]               exp_state,
      input logic [ROW_CNT_W-1:0]     exp_rows_loaded
  );
    if (state !== exp_state) begin
      $error("[%0t] FAIL %s state: got=%s exp=%s",
             $time, label, state_name(state), state_name(exp_state));
      errors = errors + 1;
    end

    if (rows_loaded !== exp_rows_loaded) begin
      $error("[%0t] FAIL %s rows_loaded: got=%0d exp=%0d",
             $time, label, rows_loaded, exp_rows_loaded);
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
    total = 17;

    $display("\n================ Coverage Summary ================");

    $write("INIT_FILL -> INIT_FILL       : %0d\n", transition_cov[0][0]); hit += transition_cov[0][0];
    $write("INIT_FILL -> RUN_BOTH        : %0d\n", transition_cov[0][1]); hit += transition_cov[0][1];

    $write("RUN_BOTH -> RUN_BOTH         : %0d\n", transition_cov[1][1]); hit += transition_cov[1][1];
    $write("RUN_BOTH -> WAIT_WRITE       : %0d\n", transition_cov[1][2]); hit += transition_cov[1][2];
    $write("RUN_BOTH -> WAIT_PROCESS     : %0d\n", transition_cov[1][3]); hit += transition_cov[1][3];
    $write("RUN_BOTH -> ADVANCE_WINDOW   : %0d\n", transition_cov[1][4]); hit += transition_cov[1][4];
    $write("RUN_BOTH -> FRAME_SWITCH     : %0d\n", transition_cov[1][5]); hit += transition_cov[1][5];

    $write("WAIT_WRITE -> WAIT_WRITE     : %0d\n", transition_cov[2][2]); hit += transition_cov[2][2];
    $write("WAIT_WRITE -> ADVANCE_WINDOW : %0d\n", transition_cov[2][4]); hit += transition_cov[2][4];
    $write("WAIT_WRITE -> FRAME_SWITCH   : %0d\n", transition_cov[2][5]); hit += transition_cov[2][5];

    $write("WAIT_PROCESS -> WAIT_PROCESS : %0d\n", transition_cov[3][3]); hit += transition_cov[3][3];
    $write("WAIT_PROCESS -> WAIT_WRITE   : %0d\n", transition_cov[3][2]); hit += transition_cov[3][2];
    $write("WAIT_PROCESS -> ADVANCE      : %0d\n", transition_cov[3][4]); hit += transition_cov[3][4];
    $write("WAIT_PROCESS -> FRAME_SWITCH : %0d\n", transition_cov[3][5]); hit += transition_cov[3][5];

    $write("ADVANCE_WINDOW -> RUN_BOTH   : %0d\n", transition_cov[4][1]); hit += transition_cov[4][1];

    $write("FRAME_SWITCH -> INIT_FILL    : %0d\n", transition_cov[5][0]); hit += transition_cov[5][0];
    $write("FRAME_SWITCH -> RUN_BOTH     : %0d\n", transition_cov[5][1]); hit += transition_cov[5][1];

    $display("--------------------------------------------------");
    $display("Defined FSM transitions:       %0d / %0d", hit, total);
    $display("Async reset checked:           %0d", async_reset_seen);
    $display("frame_done counter clear:      %0d", frame_done_clear_seen);
    $display("Next-frame rows pre-accumulated:%0d", rows_accumulated_while_processing_seen);
    $display("==================================================\n");
  endtask

  //--------------------------------------------------------------------------
  // Test sequence
  //--------------------------------------------------------------------------
  initial begin
    errors                                 = 0;
    async_reset_seen                       = 1'b0;
    frame_done_clear_seen                  = 1'b0;
    rows_accumulated_while_processing_seen = 1'b0;

    $display("== tb_window_manager_fsm ==");

    //======================================================================
    // Stage 0 -- Initial reset
    //======================================================================
    // Asynchronous reset assertion.
    resetb = 1'b0;
    #2.5ns;

    if ((state !== ST_INIT_FILL) | (rows_loaded !== '0)) begin
      $error("[%0t] FAIL async reset: state=%s rows_loaded=%0d",
             $time, state_name(state), rows_loaded);
      errors = errors + 1;
    end
    else begin
      $display("[%0t] PASS async reset assert => ST_INIT_FILL, rows_loaded=0", $time);
      async_reset_seen = 1'b1;
    end

    // Synchronized reset release.
    sync();
    resetb = 1'b1;
    #1ps;

    check_case("RESET RELEASE / BASELINE",
               ST_INIT_FILL, ST_INIT_FILL, 3'd0, 1'b0);

    //======================================================================
    // Stage 1 -- Initial fill of the first frame
    //======================================================================
    // The counter is internal to the FSM and saturates at INIT_ROWS.
    // Keep row_write_done asserted to model five consecutive completed rows.
    sync();
    expect_state_rows("INIT baseline result", ST_INIT_FILL, 3'd0);
    row_write_done = 1'b1;
    #1ps;
    check_case("INIT row 1 pending",
               ST_INIT_FILL, ST_INIT_FILL, 3'd0, 1'b0);

    sync();
    expect_state_rows("INIT row 1 result", ST_INIT_FILL, 3'd1);
    check_case("INIT row 2 pending",
               ST_INIT_FILL, ST_INIT_FILL, 3'd1, 1'b0);

    sync();
    expect_state_rows("INIT row 2 result", ST_INIT_FILL, 3'd2);
    check_case("INIT row 3 pending",
               ST_INIT_FILL, ST_INIT_FILL, 3'd2, 1'b0);

    sync();
    expect_state_rows("INIT row 3 result", ST_INIT_FILL, 3'd3);
    check_case("INIT row 4 pending",
               ST_INIT_FILL, ST_INIT_FILL, 3'd3, 1'b0);

    sync();
    expect_state_rows("INIT row 4 result", ST_INIT_FILL, 3'd4);
    check_case("INIT row 5 -> RUN_BOTH",
               ST_INIT_FILL, ST_RUN_BOTH, 3'd4, 1'b1);

    sync();
    expect_state_rows("INIT exit result", ST_RUN_BOTH, 3'd5);
    row_write_done = 1'b0;
    #1ps;

    // Counter must remain saturated at INIT_ROWS even if more real rows are
    // completed before frame_done clears it.
    check_case("RUN_BOTH baseline",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd5, 1'b0);

    //======================================================================
    // Stage 2 -- Reader runs ahead: ST_WAIT_WRITE
    //======================================================================
    sync();
    expect_state_rows("RUN baseline result", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b1;
    next_row_ready = 1'b0;
    #1ps;
    check_case("RUN_BOTH -> WAIT_WRITE",
               ST_RUN_BOTH, ST_WAIT_WRITE, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_WRITE", ST_WAIT_WRITE, 3'd5);
    process_done = 1'b0;
    #1ps;
    check_case("WAIT_WRITE no next row",
               ST_WAIT_WRITE, ST_WAIT_WRITE, 3'd5, 1'b0);

    sync();
    expect_state_rows("WAIT_WRITE hold result", ST_WAIT_WRITE, 3'd5);
    next_row_ready = 1'b1;
    #1ps;
    check_case("WAIT_WRITE -> ADVANCE",
               ST_WAIT_WRITE, ST_ADVANCE_WINDOW, 3'd5, 1'b0);

    sync();
    check_case("ADVANCE after WAIT_WRITE",
               ST_ADVANCE_WINDOW, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("ADVANCE -> RUN_BOTH", ST_RUN_BOTH, 3'd5);
    next_row_ready = 1'b0;
    #1ps;

    //======================================================================
    // Stage 3 -- Writer reaches protected margin: ST_WAIT_PROCESS
    //======================================================================
    sync();
    expect_state_rows("RUN before WAIT_PROCESS", ST_RUN_BOTH, 3'd5);
    write_blocked = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> WAIT_PROCESS",
               ST_RUN_BOTH, ST_WAIT_PROCESS, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_PROCESS", ST_WAIT_PROCESS, 3'd5);
    check_case("WAIT_PROCESS processing active",
               ST_WAIT_PROCESS, ST_WAIT_PROCESS, 3'd5, 1'b0);

    //--------------------------------------------------------------------
    // Processing completes, but no next logical row is ready.
    //--------------------------------------------------------------------
    sync();
    expect_state_rows("WAIT_PROCESS hold result", ST_WAIT_PROCESS, 3'd5);
    process_done   = 1'b1;
    next_row_ready = 1'b0;
    #1ps;
    check_case("WAIT_PROCESS -> WAIT_WRITE",
               ST_WAIT_PROCESS, ST_WAIT_WRITE, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_WRITE from WAIT_PROCESS", ST_WAIT_WRITE, 3'd5);
    process_done  = 1'b0;
    write_blocked = 1'b0;
    #1ps;
    check_case("WAIT_WRITE still waiting",
               ST_WAIT_WRITE, ST_WAIT_WRITE, 3'd5, 1'b0);

    sync();
    expect_state_rows("WAIT_WRITE second hold", ST_WAIT_WRITE, 3'd5);
    next_row_ready = 1'b1;
    #1ps;
    check_case("WAIT_WRITE -> ADVANCE #2",
               ST_WAIT_WRITE, ST_ADVANCE_WINDOW, 3'd5, 1'b0);

    sync();
    check_case("ADVANCE after WAIT_PROCESS/WAIT_WRITE",
               ST_ADVANCE_WINDOW, ST_RUN_BOTH, 3'd5, 1'b0);

    //--------------------------------------------------------------------
    // Re-enter WAIT_PROCESS and finish directly to ADVANCE_WINDOW.
    //--------------------------------------------------------------------
    sync();
    expect_state_rows("Return RUN before WAIT_PROCESS #2", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b0;
    next_row_ready = 1'b0;
    write_blocked  = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> WAIT_PROCESS #2",
               ST_RUN_BOTH, ST_WAIT_PROCESS, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_PROCESS #2", ST_WAIT_PROCESS, 3'd5);
    process_done   = 1'b1;
    next_row_ready = 1'b1;
    #1ps;
    check_case("WAIT_PROCESS -> ADVANCE",
               ST_WAIT_PROCESS, ST_ADVANCE_WINDOW, 3'd5, 1'b0);

    sync();
    check_case("ADVANCE after WAIT_PROCESS",
               ST_ADVANCE_WINDOW, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("Return RUN after WAIT_PROCESS", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b0;
    next_row_ready = 1'b0;
    write_blocked  = 1'b0;
    #1ps;

    //======================================================================
    // Stage 4 -- frame_done and next-frame accumulation during processing
    //======================================================================
    // frame_done synchronously clears rows_loaded. row_write_done is asserted
    // at the same time to verify that the counter clear has priority.
    sync();
    expect_state_rows("RUN before frame_done", ST_RUN_BOTH, 3'd5);
    frame_done     = 1'b1;
    row_write_done = 1'b1;
    #1ps;
    check_case("FRAME_DONE clear pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("FRAME_DONE clear result", ST_RUN_BOTH, 3'd0);
    frame_done_clear_seen = 1'b1;
    frame_done     = 1'b0;
    row_write_done = 1'b1;
    #1ps;

    // Five rows of the next frame are written while the previous frame is
    // still in ST_RUN_BOTH. The row counter therefore reaches INIT_ROWS before
    // the previous frame reaches ST_FRAME_SWITCH.
    check_case("NEXT FRAME row 1 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd0, 1'b0);

    sync();
    expect_state_rows("NEXT FRAME row 1 result", ST_RUN_BOTH, 3'd1);
    check_case("NEXT FRAME row 2 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd1, 1'b0);

    sync();
    expect_state_rows("NEXT FRAME row 2 result", ST_RUN_BOTH, 3'd2);
    check_case("NEXT FRAME row 3 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd2, 1'b0);

    sync();
    expect_state_rows("NEXT FRAME row 3 result", ST_RUN_BOTH, 3'd3);
    check_case("NEXT FRAME row 4 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd3, 1'b0);

    sync();
    expect_state_rows("NEXT FRAME row 4 result", ST_RUN_BOTH, 3'd4);
    check_case("NEXT FRAME row 5 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd4, 1'b1);

    sync();
    expect_state_rows("NEXT FRAME five rows ready", ST_RUN_BOTH, 3'd5);
    rows_accumulated_while_processing_seen = 1'b1;
    row_write_done = 1'b0;
    #1ps;

    //--------------------------------------------------------------------
    // Writer blocks, then the final padded window completes.
    // WAIT_PROCESS must go to FRAME_SWITCH, and because five next-frame rows
    // are already ready, FRAME_SWITCH returns directly to RUN_BOTH.
    //--------------------------------------------------------------------
    sync();
    expect_state_rows("RUN before final WAIT_PROCESS", ST_RUN_BOTH, 3'd5);
    write_blocked = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> WAIT_PROCESS before frame switch",
               ST_RUN_BOTH, ST_WAIT_PROCESS, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter final WAIT_PROCESS", ST_WAIT_PROCESS, 3'd5);
    process_done   = 1'b1;
    last_window    = 1'b1;
    next_row_ready = 1'b0;
    #1ps;
    check_case("WAIT_PROCESS -> FRAME_SWITCH",
               ST_WAIT_PROCESS, ST_FRAME_SWITCH, 3'd5, 1'b0);

    sync();
    check_case("FRAME_SWITCH -> RUN_BOTH",
               ST_FRAME_SWITCH, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("FRAME_SWITCH direct RUN result", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b0;
    last_window    = 1'b0;
    write_blocked  = 1'b0;
    #1ps;

    //======================================================================
    // Stage 5 -- Frame switch when fewer than INIT_ROWS rows are ready
    //======================================================================
    sync();
    expect_state_rows("RUN before second frame_done", ST_RUN_BOTH, 3'd5);
    frame_done = 1'b1;
    #1ps;
    check_case("SECOND FRAME_DONE clear pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("SECOND FRAME_DONE clear result", ST_RUN_BOTH, 3'd0);
    frame_done     = 1'b0;
    row_write_done = 1'b1;
    #1ps;

    // Accumulate only three rows of the following frame.
    check_case("PARTIAL NEXT FRAME row 1 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd0, 1'b0);

    sync();
    expect_state_rows("PARTIAL row 1 result", ST_RUN_BOTH, 3'd1);
    check_case("PARTIAL NEXT FRAME row 2 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd1, 1'b0);

    sync();
    expect_state_rows("PARTIAL row 2 result", ST_RUN_BOTH, 3'd2);
    check_case("PARTIAL NEXT FRAME row 3 pending",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd2, 1'b0);

    sync();
    expect_state_rows("PARTIAL row 3 result", ST_RUN_BOTH, 3'd3);
    row_write_done = 1'b0;
    #1ps;

    //--------------------------------------------------------------------
    // A completed last window has priority over write_blocked and moves to
    // FRAME_SWITCH. With only three next-frame rows ready, FRAME_SWITCH then
    // returns to INIT_FILL.
    //--------------------------------------------------------------------
    sync();
    expect_state_rows("RUN before direct FRAME_SWITCH", ST_RUN_BOTH, 3'd3);
    process_done   = 1'b1;
    last_window    = 1'b1;
    next_row_ready = 1'b0;
    write_blocked  = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> FRAME_SWITCH priority",
               ST_RUN_BOTH, ST_FRAME_SWITCH, 3'd3, 1'b0);

    sync();
    check_case("FRAME_SWITCH -> INIT_FILL",
               ST_FRAME_SWITCH, ST_INIT_FILL, 3'd3, 1'b0);

    sync();
    expect_state_rows("Enter INIT_FILL with three rows", ST_INIT_FILL, 3'd3);
    process_done   = 1'b0;
    last_window    = 1'b0;
    next_row_ready = 1'b0;
    write_blocked  = 1'b0;
    #1ps;
    check_case("INIT_FILL already has three rows",
               ST_INIT_FILL, ST_INIT_FILL, 3'd3, 1'b0);

    //--------------------------------------------------------------------
    // Complete rows four and five. rows_done must still allow immediate exit
    // from INIT_FILL even though the first three rows were accumulated before
    // entering this state.
    //--------------------------------------------------------------------
    sync();
    expect_state_rows("INIT partial-fill hold", ST_INIT_FILL, 3'd3);
    row_write_done = 1'b1;
    #1ps;
    check_case("INIT incoming row 4 pending",
               ST_INIT_FILL, ST_INIT_FILL, 3'd3, 1'b0);

    sync();
    expect_state_rows("INIT incoming row 4 result", ST_INIT_FILL, 3'd4);
    check_case("INIT incoming row 5 -> RUN",
               ST_INIT_FILL, ST_RUN_BOTH, 3'd4, 1'b1);

    sync();
    expect_state_rows("INIT partial-fill exit", ST_RUN_BOTH, 3'd5);
    row_write_done = 1'b0;
    #1ps;

    //======================================================================
    // Stage 6 -- RUN_BOTH direct ADVANCE priority over write_blocked
    //======================================================================
    sync();
    expect_state_rows("RUN before direct ADVANCE", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b1;
    next_row_ready = 1'b1;
    write_blocked  = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> ADVANCE priority",
               ST_RUN_BOTH, ST_ADVANCE_WINDOW, 3'd5, 1'b0);

    sync();
    check_case("FINAL ADVANCE -> RUN_BOTH",
               ST_ADVANCE_WINDOW, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("FINAL RUN_BOTH", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b0;
    next_row_ready = 1'b0;
    write_blocked  = 1'b0;
    #1ps;
    check_case("FINAL STABLE RUN_BOTH",
               ST_RUN_BOTH, ST_RUN_BOTH, 3'd5, 1'b0);

    //======================================================================
    // Stage 7 -- Final-window detection while already in WAIT_WRITE
    //
    // frame_done may make last_window true only after process_done has already
    // moved the FSM into WAIT_WRITE. In that case the FSM must switch frames
    // instead of waiting forever or advancing into the next frame boundary.
    //======================================================================
    sync();
    expect_state_rows("RUN before WAIT_WRITE final-window test", ST_RUN_BOTH, 3'd5);
    process_done   = 1'b1;
    next_row_ready = 1'b0;
    last_window    = 1'b0;
    #1ps;
    check_case("RUN_BOTH -> WAIT_WRITE before boundary known",
               ST_RUN_BOTH, ST_WAIT_WRITE, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_WRITE before boundary known", ST_WAIT_WRITE, 3'd5);
    process_done = 1'b0;
    last_window  = 1'b1;
    #1ps;
    check_case("WAIT_WRITE -> FRAME_SWITCH when final window appears",
               ST_WAIT_WRITE, ST_FRAME_SWITCH, 3'd5, 1'b0);

    sync();
    check_case("FRAME_SWITCH after WAIT_WRITE -> RUN_BOTH",
               ST_FRAME_SWITCH, ST_RUN_BOTH, 3'd5, 1'b0);

    sync();
    expect_state_rows("Return RUN after WAIT_WRITE frame switch", ST_RUN_BOTH, 3'd5);
    last_window = 1'b0;
    #1ps;

    //======================================================================
    // Stage 8 -- Asynchronous reset during active operation
    //======================================================================
    // Move to a non-initial state with a non-zero row count, then assert
    // reset asynchronously between clock edges. State and rows_loaded must
    // return immediately to their reset values.
    sync();
    expect_state_rows("RUN before runtime reset", ST_RUN_BOTH, 3'd5);
    write_blocked = 1'b1;
    #1ps;
    check_case("RUN_BOTH -> WAIT_PROCESS before reset",
               ST_RUN_BOTH, ST_WAIT_PROCESS, 3'd5, 1'b0);

    sync();
    expect_state_rows("Enter WAIT_PROCESS before reset", ST_WAIT_PROCESS, 3'd5);

    // Assert reset away from a clock edge to verify asynchronous behavior.
    #2.5ns;
    resetb = 1'b0;
    #1ps;

    if ((state !== ST_INIT_FILL) | (rows_loaded !== '0)) begin
      $error("[%0t] FAIL runtime async reset: state=%s rows_loaded=%0d",
             $time, state_name(state), rows_loaded);
      errors = errors + 1;
    end
    else begin
      $display("[%0t] PASS runtime async reset => ST_INIT_FILL, rows_loaded=0",
               $time);
    end

    // Release reset synchronously, then restore the blocked input.
    sync();
    resetb = 1'b1;
    #1ps;
    check_case("RUNTIME RESET RELEASE",
               ST_INIT_FILL, ST_INIT_FILL, 3'd0, 1'b0);

    sync();
    expect_state_rows("Runtime reset release result", ST_INIT_FILL, 3'd0);
    write_blocked = 1'b0;
    #1ps;
    check_case("RUNTIME RESET BASELINE",
               ST_INIT_FILL, ST_INIT_FILL, 3'd0, 1'b0);

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
