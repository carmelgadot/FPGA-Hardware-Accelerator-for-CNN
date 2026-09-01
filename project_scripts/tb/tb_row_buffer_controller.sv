`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : tb_row_buffer_controller

  Description :
    Directed integration testbench for row_buffer_controller.

    The DUT is instantiated with a short test row:
      - ROW_LENGTH  = 5
      - ADDR_WIDTH  = 3
      - INIT_ROWS   = 5
      - STRIDE      = 3
      - NUM_BUFFERS = 16
      - OCC_CNT_W   = 5

    The shortened row keeps the simulation practical while preserving the
    complete interaction between:
      1) window_manager_fsm
      2) write address counter
      3) read address counter
      4) buffer_control

  General Goals :
    - Verify asynchronous reset behavior.
    - Verify synchronized reset release.
    - Verify initial filling of INIT_ROWS real rows.
    - Verify write-address hold when data_valid is low.
    - Verify that reading starts only after INIT_ROWS rows are available.
    - Verify simultaneous read/write operation.
    - Verify row_write_done generation and delayed process_done after the final read request.
    - Verify parallel read/write activity and the case where the final read
      request is issued before the current row write completes.
    - Verify WAIT_WRITE and ADVANCE_WINDOW integration.
    - Verify circular movement of fill_buffer and top_buffer.
    - Verify all physical write-buffer positions.
    - Verify all active read-window positions.
    - Verify every logical row selecting every physical BRAM.
    - Verify frame_done together with completion of the final real row.
    - Verify logical padding reservation and row_padding generation.
    - Verify that bram_rd_en keeps the original active-window behavior even
      when some logical rows are padding.
    - Verify the final padded window and frame_switch.
    - Verify that the next frame starts from the correct physical buffer.
    - Verify a second asynchronous reset during active operation.

  Coverage :
    - Every shortened write address is exercised.
    - Every shortened read address is exercised.
    - Every physical BRAM is exercised as the active write buffer.
    - Every physical BRAM is exercised as the top of the active read window.
    - Every logical row is mapped to every physical BRAM.
    - Padding count 0 and the final stride-3 padding window are observed.
    - The integrated INIT_FILL, RUN_BOTH, WAIT_WRITE, ADVANCE_WINDOW and
      FRAME_SWITCH paths are exercised.

    ST_WAIT_PROCESS is verified in the standalone window_manager_fsm testbench.
    It is not forced hierarchically in this integration test.

  Synchronization Rule :
    - sync() is used before every runtime stimulus change.
    - resetb assertion (1 -> 0) is intentionally asynchronous and therefore
      does not use sync() immediately before the transition.
    - resetb release (0 -> 1) is performed only after sync().
*/
//==============================================================================

module tb_row_buffer_controller;

    //==========================================================================
    // Test Parameters
    //==========================================================================

    localparam int unsigned TB_ROW_LENGTH  = 5;
    localparam int unsigned TB_ADDR_WIDTH  = 3;
    localparam int unsigned TB_ROW_CNT_W   = 3;
    localparam int unsigned TB_INIT_ROWS   = 5;
    localparam int unsigned TB_STRIDE      = 3;
    localparam int unsigned TB_NUM_BUFFERS = 16;
    localparam int unsigned TB_OCC_CNT_W   = 5;

    localparam int unsigned TB_PAD_ROWS =
        TB_STRIDE - 1;

    localparam time CLK_PERIOD = 10ns;

    typedef logic [TB_NUM_BUFFERS-1:0] mask_t;

    localparam logic [TB_ADDR_WIDTH-1:0] ZERO_ADDR =
        {TB_ADDR_WIDTH{1'b0}};

    localparam logic [TB_NUM_BUFFERS-1:0] ZERO_MASK =
        {TB_NUM_BUFFERS{1'b0}};


    //==========================================================================
    // FSM State Encoding
    // Must match window_manager_fsm.
    //==========================================================================

    localparam logic [2:0]
        ST_INIT_FILL      = 3'd0,
        ST_RUN_BOTH       = 3'd1,
        ST_WAIT_WRITE     = 3'd2,
        ST_WAIT_PROCESS   = 3'd3,
        ST_ADVANCE_WINDOW = 3'd4,
        ST_FRAME_SWITCH   = 3'd5;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;
    logic data_valid;
    logic frame_done;

    logic [TB_ADDR_WIDTH-1:0]  wr_addr;
    logic [TB_ADDR_WIDTH-1:0]  rd_addr;

    logic [TB_NUM_BUFFERS-1:0] bram_wr_en;
    logic [TB_NUM_BUFFERS-1:0] bram_rd_en;

    logic [TB_NUM_BUFFERS-1:0] row_sel [0:TB_INIT_ROWS-1];
    logic [TB_INIT_ROWS-1:0]   row_padding;


    //==========================================================================
    // Internal DUT Observation
    //
    // These signals remain internal to the design interface. They are observed
    // hierarchically only to verify integration between the internal modules.
    //==========================================================================

    logic                         en_write_row;
    logic                         en_process_window;
    logic                         advance_window;
    logic                         frame_switch;

    logic                         next_row_ready;
    logic                         write_blocked;
    logic                         last_window;

    logic                         wr_valid;
    logic                         rd_valid;
    logic                         row_write_done;
    logic                         last_read_issued;
    logic                         read_pending;
    logic                         process_done;

    logic [2:0]                   state;
    logic [TB_ROW_CNT_W-1:0]      rows_loaded;

    logic [TB_NUM_BUFFERS-1:0]    fill_buffer_onehot;
    logic [TB_NUM_BUFFERS-1:0]    top_buffer_onehot;
    logic [TB_NUM_BUFFERS-1:0]    padding_mask;
    logic [TB_NUM_BUFFERS-1:0]    active_read_mask;
    logic [TB_OCC_CNT_W-1:0]      occupied_rows;


    assign en_write_row       = dut.en_write_row;
    assign en_process_window  = dut.en_process_window;
    assign advance_window     = dut.advance_window;
    assign frame_switch       = dut.frame_switch;

    assign next_row_ready     = dut.next_row_ready;
    assign write_blocked      = dut.write_blocked;
    assign last_window        = dut.last_window;

    assign wr_valid           = dut.wr_valid;
    assign rd_valid           = dut.rd_valid;
    assign row_write_done     = dut.row_write_done;
    assign last_read_issued   = dut.last_read_issued;
    assign read_pending       = dut.read_pending;
    assign process_done       = dut.process_done;

    assign state              = dut.u_window_manager_fsm.state;
    assign rows_loaded        = dut.u_window_manager_fsm.rows_loaded;

    assign fill_buffer_onehot = dut.u_buffer_control.fill_buffer_onehot;
    assign top_buffer_onehot  = dut.u_buffer_control.top_buffer_onehot;
    assign padding_mask       = dut.u_buffer_control.padding_mask;
    assign active_read_mask   = dut.u_buffer_control.active_read_mask;
    assign occupied_rows      = dut.u_buffer_control.occupied_rows;


    //==========================================================================
    // Test Status
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;


    //==========================================================================
    // Coverage Tracking
    //==========================================================================

    bit write_address_covered [0:TB_ROW_LENGTH-1];
    bit read_address_covered  [0:TB_ROW_LENGTH-1];

    bit write_position_covered [0:TB_NUM_BUFFERS-1];
    bit read_window_covered    [0:TB_NUM_BUFFERS-1];

    bit row_route_covered
        [0:TB_INIT_ROWS-1]
        [0:TB_NUM_BUFFERS-1];

    bit padding_count_covered [0:TB_PAD_ROWS];

    bit state_covered [0:5];

    bit reset_covered;
    bit reset_during_activity_covered;
    bit write_pause_covered;
    bit parallel_read_write_covered;
    bit read_drain_covered;
    bit frame_done_with_row_covered;
    bit padding_reserved_covered;
    bit final_window_covered;
    bit frame_switch_covered;
    bit next_frame_restart_covered;


    //==========================================================================
    // DUT Instance
    //==========================================================================

    row_buffer_controller #(
        .ROW_LENGTH  (TB_ROW_LENGTH),
        .ADDR_WIDTH  (TB_ADDR_WIDTH),
        .ROW_CNT_W   (TB_ROW_CNT_W),
        .INIT_ROWS   (TB_INIT_ROWS),
        .STRIDE      (TB_STRIDE),
        .NUM_BUFFERS (TB_NUM_BUFFERS),
        .OCC_CNT_W   (TB_OCC_CNT_W)
    ) dut (
        .clk         (clk),
        .resetb      (resetb),
        .data_valid  (data_valid),
        .frame_done  (frame_done),

        .wr_addr     (wr_addr),
        .rd_addr     (rd_addr),

        .bram_wr_en  (bram_wr_en),
        .bram_rd_en  (bram_rd_en),

        .row_sel     (row_sel),
        .row_padding (row_padding)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end


    //==========================================================================
    // Utility Functions
    //==========================================================================

    //--------------------------------------------------------------------------
    // Return a one-hot mask for one physical BRAM.
    //--------------------------------------------------------------------------

    function automatic mask_t onehot_buffer(
        input int unsigned buffer_idx
    );
        mask_t result;

        begin
            result = ZERO_MASK;
            result[buffer_idx] = 1'b1;
            onehot_buffer = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Return the active read mask for one top-buffer position.
    //--------------------------------------------------------------------------

    function automatic mask_t expected_read_mask(
        input int unsigned top_idx
    );
        mask_t result;
        int unsigned logical_row;
        int unsigned physical_buffer;

        begin
            result = ZERO_MASK;

            for (logical_row = 0;
                 logical_row < TB_INIT_ROWS;
                 logical_row = logical_row + 1) begin

                physical_buffer =
                    (top_idx + logical_row) % TB_NUM_BUFFERS;

                result[physical_buffer] = 1'b1;
            end

            expected_read_mask = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Return a padding mask containing TB_PAD_ROWS consecutive physical slots.
    //--------------------------------------------------------------------------

    function automatic mask_t expected_padding_mask(
        input int unsigned first_padding_idx
    );
        mask_t result;
        int unsigned pad_idx;
        int unsigned physical_buffer;

        begin
            result = ZERO_MASK;

            for (pad_idx = 0;
                 pad_idx < TB_PAD_ROWS;
                 pad_idx = pad_idx + 1) begin

                physical_buffer =
                    (first_padding_idx + pad_idx) % TB_NUM_BUFFERS;

                result[physical_buffer] = 1'b1;
            end

            expected_padding_mask = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Return the logical padding indication for the current active window.
    //--------------------------------------------------------------------------

    function automatic logic [TB_INIT_ROWS-1:0] expected_row_padding(
        input int unsigned top_idx,
        input mask_t      expected_pad_mask
    );
        logic [TB_INIT_ROWS-1:0] result;
        int unsigned logical_row;
        int unsigned physical_buffer;

        begin
            result = {TB_INIT_ROWS{1'b0}};

            for (logical_row = 0;
                 logical_row < TB_INIT_ROWS;
                 logical_row = logical_row + 1) begin

                physical_buffer =
                    (top_idx + logical_row) % TB_NUM_BUFFERS;

                result[logical_row] =
                    expected_pad_mask[physical_buffer];
            end

            expected_row_padding = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Count the number of padding rows currently present in the active window.
    //--------------------------------------------------------------------------

    function automatic int unsigned padding_count(
        input logic [TB_INIT_ROWS-1:0] value
    );
        int unsigned result;
        int unsigned idx;

        begin
            result = 0;

            for (idx = 0;
                 idx < TB_INIT_ROWS;
                 idx = idx + 1)
                result = result + value[idx];

            padding_count = result;
        end
    endfunction


    //--------------------------------------------------------------------------
    // State-name helper.
    //--------------------------------------------------------------------------

    function automatic string state_name(
        input logic [2:0] state_value
    );
        case (state_value)
            ST_INIT_FILL:
                return "ST_INIT_FILL";
            ST_RUN_BOTH:
                return "ST_RUN_BOTH";
            ST_WAIT_WRITE:
                return "ST_WAIT_WRITE";
            ST_WAIT_PROCESS:
                return "ST_WAIT_PROCESS";
            ST_ADVANCE_WINDOW:
                return "ST_ADVANCE_WINDOW";
            ST_FRAME_SWITCH:
                return "ST_FRAME_SWITCH";
            default:
                return "UNKNOWN_STATE";
        endcase
    endfunction


    //--------------------------------------------------------------------------
    // Expected FSM output helpers.
    //--------------------------------------------------------------------------

    function automatic logic expected_en_write(
        input logic [2:0] state_value,
        input logic       blocked
    );
        case (state_value)
            ST_INIT_FILL,
            ST_RUN_BOTH,
            ST_WAIT_WRITE,
            ST_ADVANCE_WINDOW,
            ST_FRAME_SWITCH:
                return ~blocked;

            default:
                return 1'b0;
        endcase
    endfunction


    function automatic logic expected_en_process(
        input logic [2:0] state_value
    );
        case (state_value)
            ST_RUN_BOTH,
            ST_WAIT_PROCESS:
                return 1'b1;

            default:
                return 1'b0;
        endcase
    endfunction


    // Return whether the current top position is the final STRIDE output group.
    // The next-frame boundary is identified as the first non-padding slot
    // immediately following the reserved tail-padding region.
    function automatic logic expected_last_window(
        input int unsigned top_idx,
        input mask_t       pad_mask
    );
        int unsigned candidate_idx;
        int unsigned previous_idx;
        int unsigned pad_idx;
        int unsigned distance;
        logic boundary_found;

        begin
            expected_last_window = 1'b0;

            if (pad_mask != ZERO_MASK) begin
                for (candidate_idx = 0;
                     candidate_idx < TB_NUM_BUFFERS;
                     candidate_idx = candidate_idx + 1) begin

                    boundary_found = ~pad_mask[candidate_idx];

                    for (pad_idx = 1;
                         pad_idx <= TB_PAD_ROWS;
                         pad_idx = pad_idx + 1) begin

                        previous_idx =
                            (candidate_idx + TB_NUM_BUFFERS - pad_idx) %
                            TB_NUM_BUFFERS;

                        boundary_found =
                            boundary_found & pad_mask[previous_idx];
                    end

                    if (boundary_found) begin
                        distance =
                            (candidate_idx + TB_NUM_BUFFERS - top_idx) %
                            TB_NUM_BUFFERS;

                        if ((distance >= TB_INIT_ROWS) &&
                            (distance < (TB_INIT_ROWS + TB_STRIDE)))
                            expected_last_window = 1'b1;
                    end
                end
            end
        end
    endfunction


    //==========================================================================
    // Utility Tasks
    //==========================================================================

    //--------------------------------------------------------------------------
    // Synchronize to the next rising edge and allow DUT settling.
    //--------------------------------------------------------------------------

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //--------------------------------------------------------------------------
    // Print a test banner.
    //--------------------------------------------------------------------------

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
    // Check one boolean condition.
    //--------------------------------------------------------------------------

    task automatic check_condition(
        input string what,
        input logic  condition_ok
    );
        begin
            check_count = check_count + 1;

            if (!condition_ok) begin
                error_count = error_count + 1;
                $error("[%0t] FAIL: %s", $time, what);
            end
            else
                $display("[%0t] PASS: %s", $time, what);
        end
    endtask


    //--------------------------------------------------------------------------
    // Check all external outputs and the important internal integration signals.
    //--------------------------------------------------------------------------

    task automatic check_controller(
        input string       label,
        input int unsigned expected_wr_addr,
        input int unsigned expected_rd_addr,
        input int unsigned fill_idx,
        input int unsigned top_idx,
        input int unsigned expected_occupied_rows,
        input mask_t       expected_pad_mask,
        input logic [2:0]  expected_state,
        input int unsigned expected_rows_loaded
    );
        logic expected_blocked;
        logic expected_next_ready;
        logic expected_write_enable;
        logic expected_read_enable;
        logic expected_wr_valid;
        logic expected_rd_valid;
        logic expected_row_done;
        logic expected_last_read_issued;
        logic expected_process_done;
        logic expected_advance;
        logic expected_switch;
        logic expected_last;

        mask_t expected_wr_en;
        mask_t expected_rd_en;
        mask_t expected_row_sel_mask;

        logic [TB_INIT_ROWS-1:0] expected_padding;

        int unsigned logical_row;
        int unsigned physical_buffer;
        int unsigned pad_count;

        begin
            expected_blocked =
                (expected_occupied_rows >=
                 (TB_NUM_BUFFERS - TB_PAD_ROWS));

            expected_next_ready =
                (expected_occupied_rows >= (TB_INIT_ROWS + TB_STRIDE));

            expected_write_enable =
                expected_en_write(
                    expected_state,
                    expected_blocked
                );

            expected_read_enable =
                expected_en_process(expected_state);

            expected_wr_valid =
                expected_write_enable & data_valid;

            expected_rd_valid =
                expected_read_enable & ~read_pending;

            expected_row_done =
                expected_wr_valid &
                (expected_wr_addr == (TB_ROW_LENGTH - 1));

            expected_last_read_issued =
                expected_rd_valid &
                (expected_rd_addr == (TB_ROW_LENGTH - 1));

            expected_process_done = read_pending;

            expected_advance =
                (expected_state == ST_ADVANCE_WINDOW);

            expected_switch =
                (expected_state == ST_FRAME_SWITCH);

            expected_wr_en = ZERO_MASK;
            expected_rd_en = ZERO_MASK;

            if (expected_wr_valid)
                expected_wr_en = onehot_buffer(fill_idx);

            if (expected_rd_valid)
                expected_rd_en = expected_read_mask(top_idx);

            expected_padding =
                expected_row_padding(
                    top_idx,
                    expected_pad_mask
                );

            expected_last =
                expected_last_window(
                    top_idx,
                    expected_pad_mask
                );


            //------------------------------------------------------------------
            // External address outputs
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (wr_addr !== expected_wr_addr) begin
                error_count = error_count + 1;
                $error(
                    "[%0t] FAIL %s wr_addr: expected=%0d got=%0d",
                    $time,
                    label,
                    expected_wr_addr,
                    wr_addr
                );
            end

            check_count = check_count + 1;

            if (rd_addr !== expected_rd_addr) begin
                error_count = error_count + 1;
                $error(
                    "[%0t] FAIL %s rd_addr: expected=%0d got=%0d",
                    $time,
                    label,
                    expected_rd_addr,
                    rd_addr
                );
            end


            //------------------------------------------------------------------
            // External BRAM enables
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (bram_wr_en !== expected_wr_en) begin
                error_count = error_count + 1;
                $error(
                    "[%0t] FAIL %s bram_wr_en: expected=%b got=%b",
                    $time,
                    label,
                    expected_wr_en,
                    bram_wr_en
                );
            end

            check_count = check_count + 1;

            if (bram_rd_en !== expected_rd_en) begin
                error_count = error_count + 1;
                $error(
                    "[%0t] FAIL %s bram_rd_en: expected=%b got=%b",
                    $time,
                    label,
                    expected_rd_en,
                    bram_rd_en
                );
            end


            //------------------------------------------------------------------
            // Logical-row selectors
            //------------------------------------------------------------------

            for (logical_row = 0;
                 logical_row < TB_INIT_ROWS;
                 logical_row = logical_row + 1) begin

                physical_buffer =
                    (top_idx + logical_row) % TB_NUM_BUFFERS;

                expected_row_sel_mask =
                    onehot_buffer(physical_buffer);

                check_count = check_count + 1;

                if (row_sel[logical_row] !==
                    expected_row_sel_mask) begin

                    error_count = error_count + 1;

                    $error(
                        "[%0t] FAIL %s row_sel[%0d]: expected=%b got=%b",
                        $time,
                        label,
                        logical_row,
                        expected_row_sel_mask,
                        row_sel[logical_row]
                    );
                end
                else begin
                    row_route_covered
                        [logical_row]
                        [physical_buffer] = 1'b1;
                end
            end


            //------------------------------------------------------------------
            // Padding output
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (row_padding !== expected_padding) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s row_padding: expected=%b got=%b",
                    $time,
                    label,
                    expected_padding,
                    row_padding
                );
            end
            else begin
                pad_count = padding_count(expected_padding);

                if (pad_count <= TB_PAD_ROWS)
                    padding_count_covered[pad_count] = 1'b1;
            end


            //------------------------------------------------------------------
            // FSM / handshake integration
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (state !== expected_state) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s state: expected=%s got=%s",
                    $time,
                    label,
                    state_name(expected_state),
                    state_name(state)
                );
            end
            else
                state_covered[expected_state] = 1'b1;


            check_count = check_count + 1;

            if (en_write_row !== expected_write_enable) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s en_write_row: expected=%b got=%b",
                    $time,
                    label,
                    expected_write_enable,
                    en_write_row
                );
            end

            check_count = check_count + 1;

            if (en_process_window !== expected_read_enable) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s en_process_window: expected=%b got=%b",
                    $time,
                    label,
                    expected_read_enable,
                    en_process_window
                );
            end

            check_count = check_count + 1;

            if (advance_window !== expected_advance) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s advance_window: expected=%b got=%b",
                    $time,
                    label,
                    expected_advance,
                    advance_window
                );
            end

            check_count = check_count + 1;

            if (frame_switch !== expected_switch) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s frame_switch: expected=%b got=%b",
                    $time,
                    label,
                    expected_switch,
                    frame_switch
                );
            end

            check_count = check_count + 1;

            if (wr_valid !== expected_wr_valid) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s wr_valid: expected=%b got=%b",
                    $time,
                    label,
                    expected_wr_valid,
                    wr_valid
                );
            end

            check_count = check_count + 1;

            if (rd_valid !== expected_rd_valid) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s rd_valid: expected=%b got=%b",
                    $time,
                    label,
                    expected_rd_valid,
                    rd_valid
                );
            end

            check_count = check_count + 1;

            if (row_write_done !== expected_row_done) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s row_write_done: expected=%b got=%b",
                    $time,
                    label,
                    expected_row_done,
                    row_write_done
                );
            end

            check_count = check_count + 1;

            if (last_read_issued !== expected_last_read_issued) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s last_read_issued: expected=%b got=%b",
                    $time,
                    label,
                    expected_last_read_issued,
                    last_read_issued
                );
            end

            check_count = check_count + 1;

            if (process_done !== expected_process_done) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s process_done: expected=%b got=%b",
                    $time,
                    label,
                    expected_process_done,
                    process_done
                );
            end


            //------------------------------------------------------------------
            // Buffer-control integration
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (fill_buffer_onehot !== onehot_buffer(fill_idx)) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s fill_buffer_onehot: expected=%b got=%b",
                    $time,
                    label,
                    onehot_buffer(fill_idx),
                    fill_buffer_onehot
                );
            end

            check_count = check_count + 1;

            if (top_buffer_onehot !== onehot_buffer(top_idx)) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s top_buffer_onehot: expected=%b got=%b",
                    $time,
                    label,
                    onehot_buffer(top_idx),
                    top_buffer_onehot
                );
            end

            check_count = check_count + 1;

            if (padding_mask !== expected_pad_mask) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s padding_mask: expected=%b got=%b",
                    $time,
                    label,
                    expected_pad_mask,
                    padding_mask
                );
            end

            check_count = check_count + 1;

            if (active_read_mask !== expected_read_mask(top_idx)) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s active_read_mask: expected=%b got=%b",
                    $time,
                    label,
                    expected_read_mask(top_idx),
                    active_read_mask
                );
            end

            check_count = check_count + 1;

            if (occupied_rows !== expected_occupied_rows) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s occupied_rows: expected=%0d got=%0d",
                    $time,
                    label,
                    expected_occupied_rows,
                    occupied_rows
                );
            end

            check_count = check_count + 1;

            if (next_row_ready !== expected_next_ready) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s next_row_ready: expected=%b got=%b",
                    $time,
                    label,
                    expected_next_ready,
                    next_row_ready
                );
            end

            check_count = check_count + 1;

            if (write_blocked !== expected_blocked) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s write_blocked: expected=%b got=%b",
                    $time,
                    label,
                    expected_blocked,
                    write_blocked
                );
            end

            check_count = check_count + 1;

            if (last_window !== expected_last) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s last_window: expected=%b got=%b",
                    $time,
                    label,
                    expected_last,
                    last_window
                );
            end


            //------------------------------------------------------------------
            // Incoming-frame row counter
            //------------------------------------------------------------------

            check_count = check_count + 1;

            if (rows_loaded !== expected_rows_loaded) begin
                error_count = error_count + 1;

                $error(
                    "[%0t] FAIL %s rows_loaded: expected=%0d got=%0d",
                    $time,
                    label,
                    expected_rows_loaded,
                    rows_loaded
                );
            end


            //------------------------------------------------------------------
            // Structural coverage
            //------------------------------------------------------------------

            if (expected_wr_valid) begin
                write_position_covered[fill_idx] = 1'b1;

                if (expected_wr_addr < TB_ROW_LENGTH)
                    write_address_covered[expected_wr_addr] = 1'b1;
            end

            if (expected_rd_valid) begin
                read_window_covered[top_idx] = 1'b1;

                if (expected_rd_addr < TB_ROW_LENGTH)
                    read_address_covered[expected_rd_addr] = 1'b1;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Write one complete row while the FSM is in ST_INIT_FILL.
    //
    // The task starts immediately after a sync() point with data_valid low and
    // returns immediately after the row-completion edge with data_valid low.
    //--------------------------------------------------------------------------

    task automatic write_initial_row(
        inout int unsigned fill_idx,
        inout int unsigned occupied_count,
        inout int unsigned loaded_count,
        input int unsigned top_idx
    );
        int unsigned address_idx;
        logic [2:0] expected_state_after;

        begin
            sync();

            data_valid = 1'b1;
            #1ps;

            check_controller(
                "Initial-fill row address 0",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_INIT_FILL,
                loaded_count
            );

            for (address_idx = 1;
                 address_idx < TB_ROW_LENGTH;
                 address_idx = address_idx + 1) begin

                sync();

                check_controller(
                    "Initial-fill row address",
                    address_idx,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    ZERO_MASK,
                    ST_INIT_FILL,
                    loaded_count
                );
            end

            sync();

            fill_idx =
                (fill_idx + 1) % TB_NUM_BUFFERS;

            occupied_count = occupied_count + 1;

            if (loaded_count < TB_INIT_ROWS)
                loaded_count = loaded_count + 1;

            if (loaded_count == TB_INIT_ROWS)
                expected_state_after = ST_RUN_BOTH;
            else
                expected_state_after = ST_INIT_FILL;

            data_valid = 1'b0;
            #1ps;

            check_controller(
                "After initial-fill row completion",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                expected_state_after,
                loaded_count
            );
        end
    endtask


    //--------------------------------------------------------------------------
    // Complete one normal integrated read/write window.
    //
    // Start condition:
    //   - ST_RUN_BOTH
    //   - wr_addr = 0
    //   - rd_addr = 0
    //   - data_valid = 0
    //   - occupied_count = INIT_ROWS
    //
    // data_valid is changed only after sync(). Therefore the read side gets one
    // cycle head start and issues the final read request first. process_done is
    // delayed by one drain cycle before the FSM reacts to the completed scan.
    //--------------------------------------------------------------------------

    task automatic complete_normal_window(
        inout int unsigned fill_idx,
        inout int unsigned top_idx,
        inout int unsigned occupied_count,
        input int unsigned loaded_count
    );
        int unsigned address_idx;
        int unsigned extra_row_idx;

        begin
            // Every data_valid change is preceded by sync().
            // During this synchronized idle edge, the read side advances once
            // because RUN_BOTH is already active.
            sync();

            data_valid = 1'b1;
            #1ps;

            check_controller(
                "Normal parallel window start",
                0,
                1,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_RUN_BOTH,
                loaded_count
            );

            parallel_read_write_covered = 1'b1;

            // Read and write now advance together. Because the read counter had
            // one-cycle head start, it reaches the final address first.
            for (address_idx = 1;
                 address_idx < (TB_ROW_LENGTH - 1);
                 address_idx = address_idx + 1) begin

                sync();

                check_controller(
                    "Normal parallel scan",
                    address_idx,
                    address_idx + 1,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    ZERO_MASK,
                    ST_RUN_BOTH,
                    loaded_count
                );
            end

            // The final read request is issued here, but process_done is
            // delayed by one cycle so the registered BRAM output can drain.
            check_condition(
                "Final read is issued before process_done",
                last_read_issued & ~process_done
            );

            sync();

            check_controller(
                "BRAM drain after final read request",
                TB_ROW_LENGTH - 1,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_RUN_BOTH,
                loaded_count
            );

            check_condition(
                "BRAM reads stop while the final read is pending",
                read_pending & process_done & ~rd_valid & (bram_rd_en == ZERO_MASK)
            );

            read_drain_covered = 1'b1;

            // process_done and row_write_done are consumed together. The FSM
            // enters WAIT_WRITE, and the completed row becomes available.
            sync();

            fill_idx =
                (fill_idx + 1) % TB_NUM_BUFFERS;

            occupied_count = occupied_count + 1;

            data_valid = 1'b0;
            #1ps;

            check_controller(
                "WAIT_WRITE after delayed read and row completion",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_WAIT_WRITE,
                loaded_count
            );

            // STRIDE rows must be available beyond the current window before
            // the processing window can advance. Write the remaining rows
            // while the FSM waits in ST_WAIT_WRITE.
            for (extra_row_idx = 1;
                 extra_row_idx < TB_STRIDE;
                 extra_row_idx = extra_row_idx + 1) begin

                sync();

                data_valid = 1'b1;
                #1ps;

                check_controller(
                    "Additional row while waiting for next window",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    ZERO_MASK,
                    ST_WAIT_WRITE,
                    loaded_count
                );

                for (address_idx = 1;
                     address_idx < TB_ROW_LENGTH;
                     address_idx = address_idx + 1) begin

                    sync();

                    check_controller(
                        "Additional waiting-row write",
                        address_idx,
                        0,
                        fill_idx,
                        top_idx,
                        occupied_count,
                        ZERO_MASK,
                        ST_WAIT_WRITE,
                        loaded_count
                    );
                end

                sync();

                fill_idx =
                    (fill_idx + 1) % TB_NUM_BUFFERS;

                occupied_count = occupied_count + 1;

                data_valid = 1'b0;
                #1ps;

                check_controller(
                    "After additional waiting-row completion",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    ZERO_MASK,
                    ST_WAIT_WRITE,
                    loaded_count
                );
            end

            // STRIDE additional rows are now available, so WAIT_WRITE moves
            // to ADVANCE_WINDOW.
            sync();

            check_controller(
                "ADVANCE_WINDOW pulse",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_ADVANCE_WINDOW,
                loaded_count
            );

            // advance_window is consumed by buffer_control on this edge.
            sync();

            top_idx =
                (top_idx + TB_STRIDE) % TB_NUM_BUFFERS;

            occupied_count = occupied_count - TB_STRIDE;

            check_controller(
                "RUN_BOTH after normal window advance",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_RUN_BOTH,
                loaded_count
            );
        end
    endtask


    //--------------------------------------------------------------------------
    // Complete one read-only window while padding is active.
    //
    // data_valid remains low. A non-final window goes through ADVANCE_WINDOW.
    // A final window may contain zero, one, or two logical tail-padding rows
    // and goes through FRAME_SWITCH because no next-frame rows are written here.
    //--------------------------------------------------------------------------

    task automatic complete_padding_window(
        inout int unsigned top_idx,
        inout int unsigned occupied_count,
        input int unsigned fill_idx,
        input mask_t       expected_pad_mask,
        input int unsigned loaded_count,
        input logic        final_window
    );
        int unsigned address_idx;

        begin
            check_controller(
                "Padding window address 0",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                expected_pad_mask,
                ST_RUN_BOTH,
                loaded_count
            );

            for (address_idx = 1;
                 address_idx < TB_ROW_LENGTH;
                 address_idx = address_idx + 1) begin

                sync();

                check_controller(
                    "Padding-window read scan",
                    0,
                    address_idx,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    expected_pad_mask,
                    ST_RUN_BOTH,
                    loaded_count
                );
            end

            // Hold the current row mapping for one drain cycle after the final
            // BRAM read request. process_done is asserted during this cycle.
            sync();

            check_controller(
                "Padding-window BRAM drain",
                0,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                expected_pad_mask,
                ST_RUN_BOTH,
                loaded_count
            );

            if (final_window) begin

                check_condition(
                    "Final padded window is detected before completion",
                    last_window
                );

                final_window_covered = 1'b1;

                // Consume process_done. The FSM enters FRAME_SWITCH.
                sync();

                check_controller(
                    "FRAME_SWITCH pulse",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    expected_pad_mask,
                    ST_FRAME_SWITCH,
                    loaded_count
                );

                frame_switch_covered = 1'b1;

                // frame_switch is consumed by buffer_control on this edge.
                sync();

                occupied_count =
                    occupied_count -
                    (TB_PAD_ROWS +
                     (TB_INIT_ROWS -
                      padding_count(
                          expected_row_padding(
                              top_idx,
                              expected_pad_mask
                          )
                      )));

                top_idx = fill_idx;

                check_controller(
                    "After frame switch",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    ZERO_MASK,
                    ST_INIT_FILL,
                    loaded_count
                );
            end
            else begin

                // Consume process_done. Because another logical row exists,
                // the FSM enters the one-cycle ADVANCE_WINDOW state directly.
                sync();

                check_controller(
                    "Advance after non-final padding window",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    expected_pad_mask,
                    ST_ADVANCE_WINDOW,
                    loaded_count
                );

                sync();

                top_idx =
                    (top_idx + TB_STRIDE) % TB_NUM_BUFFERS;

                occupied_count = occupied_count - TB_STRIDE;

                check_controller(
                    "Next padded window",
                    0,
                    0,
                    fill_idx,
                    top_idx,
                    occupied_count,
                    expected_pad_mask,
                    ST_RUN_BOTH,
                    loaded_count
                );
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Check that all required structural coverage was reached.
    //--------------------------------------------------------------------------

    task automatic check_structural_coverage;
        int unsigned address_idx;
        int unsigned buffer_idx;
        int unsigned logical_row;
        int unsigned pad_count_idx;

        begin
            for (address_idx = 0;
                 address_idx < TB_ROW_LENGTH;
                 address_idx = address_idx + 1) begin

                check_condition(
                    $sformatf(
                        "Write address %0d covered",
                        address_idx
                    ),
                    write_address_covered[address_idx]
                );

                check_condition(
                    $sformatf(
                        "Read address %0d covered",
                        address_idx
                    ),
                    read_address_covered[address_idx]
                );
            end


            for (buffer_idx = 0;
                 buffer_idx < TB_NUM_BUFFERS;
                 buffer_idx = buffer_idx + 1) begin

                check_condition(
                    $sformatf(
                        "BRAM%0d covered as write buffer",
                        buffer_idx
                    ),
                    write_position_covered[buffer_idx]
                );

                check_condition(
                    $sformatf(
                        "BRAM%0d covered as read-window top",
                        buffer_idx
                    ),
                    read_window_covered[buffer_idx]
                );
            end


            for (logical_row = 0;
                 logical_row < TB_INIT_ROWS;
                 logical_row = logical_row + 1) begin

                for (buffer_idx = 0;
                     buffer_idx < TB_NUM_BUFFERS;
                     buffer_idx = buffer_idx + 1) begin

                    check_condition(
                        $sformatf(
                            "Logical row %0d mapped to BRAM%0d",
                            logical_row,
                            buffer_idx
                        ),
                        row_route_covered
                            [logical_row]
                            [buffer_idx]
                    );
                end
            end


            check_condition(
                "Padding count 0 observed",
                padding_count_covered[0]
            );

            check_condition(
                $sformatf(
                    "Final stride-%0d padding count observed",
                    TB_STRIDE
                ),
                padding_count_covered[TB_INIT_ROWS-TB_STRIDE]
            );
        end
    endtask


    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    initial begin : main_test

        int unsigned fill_idx;
        int unsigned top_idx;
        int unsigned occupied_count;
        int unsigned loaded_count;

        int unsigned window_idx;
        int unsigned address_idx;
        int unsigned padding_start_idx;

        mask_t expected_pad_mask;


        //----------------------------------------------------------------------
        // Initial values
        //----------------------------------------------------------------------

        resetb    = 1'b1;
        data_valid = 1'b0;
        frame_done = 1'b0;

        error_count = 0;
        check_count = 0;

        fill_idx       = 0;
        top_idx        = 0;
        occupied_count = 0;
        loaded_count   = 0;

        reset_covered                  = 1'b0;
        reset_during_activity_covered  = 1'b0;
        write_pause_covered            = 1'b0;
        parallel_read_write_covered    = 1'b0;
        read_drain_covered             = 1'b0;
        frame_done_with_row_covered    = 1'b0;
        padding_reserved_covered       = 1'b0;
        final_window_covered           = 1'b0;
        frame_switch_covered           = 1'b0;
        next_frame_restart_covered     = 1'b0;

        for (address_idx = 0;
             address_idx < TB_ROW_LENGTH;
             address_idx = address_idx + 1) begin

            write_address_covered[address_idx] = 1'b0;
            read_address_covered[address_idx]  = 1'b0;
        end

        for (window_idx = 0;
             window_idx < TB_NUM_BUFFERS;
             window_idx = window_idx + 1) begin

            write_position_covered[window_idx] = 1'b0;
            read_window_covered[window_idx]    = 1'b0;
        end

        for (window_idx = 0;
             window_idx <= TB_PAD_ROWS;
             window_idx = window_idx + 1)
            padding_count_covered[window_idx] = 1'b0;

        for (window_idx = 0;
             window_idx < 6;
             window_idx = window_idx + 1)
            state_covered[window_idx] = 1'b0;

        for (address_idx = 0;
             address_idx < TB_INIT_ROWS;
             address_idx = address_idx + 1) begin

            for (window_idx = 0;
                 window_idx < TB_NUM_BUFFERS;
                 window_idx = window_idx + 1) begin

                row_route_covered
                    [address_idx]
                    [window_idx] = 1'b0;
            end
        end


        //======================================================================
        // TEST 1
        // Initial asynchronous reset and synchronized release
        //======================================================================

        print_banner("TEST 1 - Initial asynchronous reset");

        #(CLK_PERIOD / 4);

        resetb = 1'b0;

        #1ps;

        check_controller(
            "Initial asynchronous reset",
            0,
            0,
            0,
            0,
            0,
            ZERO_MASK,
            ST_INIT_FILL,
            0
        );

        reset_covered = 1'b1;

        // Reset release is allowed only immediately after sync().
        sync();

        resetb = 1'b1;

        #1ps;

        check_controller(
            "Immediately after synchronized reset release",
            0,
            0,
            0,
            0,
            0,
            ZERO_MASK,
            ST_INIT_FILL,
            0
        );

        sync();

        check_controller(
            "Stable after reset release",
            0,
            0,
            0,
            0,
            0,
            ZERO_MASK,
            ST_INIT_FILL,
            0
        );


        //======================================================================
        // TEST 2
        // Initial fill and write-address pause
        //======================================================================

        print_banner("TEST 2 - Initial fill and write-address pause");

        // Start the first row only after an explicit synchronization point.
        sync();

        data_valid = 1'b1;
        #1ps;

        check_controller(
            "First row address 0",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );

        // Advance once, then pause data_valid.
        sync();

        check_controller(
            "First row address 1",
            1,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );

        data_valid = 1'b0;
        #1ps;

        check_controller(
            "Write disabled after synchronized data_valid drop",
            1,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );

        sync();

        check_controller(
            "Write address holds while data_valid is low",
            1,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );

        write_pause_covered = 1'b1;

        // Resume the row immediately after sync().
        data_valid = 1'b1;
        #1ps;

        for (address_idx = 2;
             address_idx < TB_ROW_LENGTH;
             address_idx = address_idx + 1) begin

            sync();

            check_controller(
                "First row resumed",
                address_idx,
                0,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_INIT_FILL,
                loaded_count
            );
        end

        // Complete first row.
        sync();

        fill_idx =
            (fill_idx + 1) % TB_NUM_BUFFERS;

        occupied_count = occupied_count + 1;
        loaded_count   = loaded_count + 1;

        data_valid = 1'b0;
        #1ps;

        check_controller(
            "After first completed row",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );


        // Complete rows 2..5.
        while (loaded_count < TB_INIT_ROWS)
            write_initial_row(
                fill_idx,
                occupied_count,
                loaded_count,
                top_idx
            );

        check_condition(
            "Processing starts only after INIT_ROWS complete rows",
            (state == ST_RUN_BOTH) &
            (rows_loaded == TB_INIT_ROWS) &
            (occupied_rows == TB_INIT_ROWS) &
            en_process_window
        );


        //======================================================================
        // TEST 3
        // Full circular integration sweep
        //
        // Perform one complete physical-buffer rotation. This exercises every
        // fill-buffer position, every active-window top position, and every
        // logical-row/physical-BRAM routing combination.
        //======================================================================

        print_banner("TEST 3 - Full circular integration sweep");

        for (window_idx = 0;
             window_idx < TB_NUM_BUFFERS;
             window_idx = window_idx + 1) begin

            complete_normal_window(
                fill_idx,
                top_idx,
                occupied_count,
                loaded_count
            );
        end

        check_condition(
            "Top pointer wrapped to BRAM0",
            top_idx == 0
        );

        check_condition(
            "Fill pointer returned to BRAM5 after full sweep",
            fill_idx == TB_INIT_ROWS
        );

        check_condition(
            "Occupancy returned to exactly INIT_ROWS",
            occupied_count == TB_INIT_ROWS
        );


        //======================================================================
        // TEST 4
        // frame_done together with final real-row completion
        //
        // A final real row is written while the current window is read.
        // frame_done is asserted only after sync(), at the final row address,
        // so frame_done and row_write_done are consumed on the same edge.
        //======================================================================

        print_banner("TEST 4 - frame_done with final real-row completion");

        // Synchronize before enabling the final real-row write.
        // RUN_BOTH advances the read side during this edge, so the read scan is
        // intentionally one address ahead of the write scan.
        sync();

        data_valid = 1'b1;
        #1ps;

        check_controller(
            "Final real row starts during active read",
            0,
            1,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_RUN_BOTH,
            loaded_count
        );

        for (address_idx = 1;
             address_idx < (TB_ROW_LENGTH - 1);
             address_idx = address_idx + 1) begin

            sync();

            check_controller(
                "Final real row parallel scan",
                address_idx,
                address_idx + 1,
                fill_idx,
                top_idx,
                occupied_count,
                ZERO_MASK,
                ST_RUN_BOTH,
                loaded_count
            );
        end

        // The final read request is issued first. One drain cycle keeps the
        // current row mapping unchanged while the writer reaches its final
        // address and process_done becomes active.
        sync();

        check_controller(
            "Final real row BRAM drain",
            TB_ROW_LENGTH - 1,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_RUN_BOTH,
            loaded_count
        );

        // frame_done changes immediately after sync(), exactly when
        // row_write_done and the delayed process_done are already asserted.
        frame_done = 1'b1;
        #1ps;

        check_condition(
            "frame_done is asserted together with row_write_done",
            frame_done & row_write_done
        );

        frame_done_with_row_covered = 1'b1;

        // The padding begins one physical slot after the final real row.
        padding_start_idx =
            (fill_idx + 1) % TB_NUM_BUFFERS;

        expected_pad_mask =
            expected_padding_mask(padding_start_idx);

        // Consume row_write_done and frame_done together.
        sync();

        fill_idx =
            (fill_idx + TB_PAD_ROWS + 1) % TB_NUM_BUFFERS;

        occupied_count =
            occupied_count + TB_PAD_ROWS + 1;

        loaded_count = 0;

        data_valid = 1'b0;
        frame_done = 1'b0;
        #1ps;

        check_controller(
            "Padding reserved after frame_done",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            expected_pad_mask,
            ST_WAIT_WRITE,
            loaded_count
        );

        check_condition(
            "Exactly PAD_ROWS physical slots are reserved",
            padding_mask == expected_pad_mask
        );

        padding_reserved_covered = 1'b1;

        // The completed real row and padding slots make the next logical row
        // available, so WAIT_WRITE moves to ADVANCE_WINDOW.
        sync();

        check_controller(
            "Advance after frame-end completion",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            expected_pad_mask,
            ST_ADVANCE_WINDOW,
            loaded_count
        );

        sync();

        top_idx =
            (top_idx + TB_STRIDE) % TB_NUM_BUFFERS;

        occupied_count = occupied_count - TB_STRIDE;

        check_controller(
            "First window after frame-end advance",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            expected_pad_mask,
            ST_RUN_BOTH,
            loaded_count
        );


        //======================================================================
        // TEST 5
        // Padding progression and frame switch
        //
        // No rows of the next frame are written here. This test uses the
        // RRRPP final-window case and frame_switch returns the controller to
        // ST_INIT_FILL.
        //======================================================================

        print_banner("TEST 5 - Padding progression and frame switch");

        // After the STRIDE-row advance above, the active window is:
        //   [real, real, real, PAD, PAD]
        complete_padding_window(
            top_idx,
            occupied_count,
            fill_idx,
            expected_pad_mask,
            loaded_count,
            1'b1
        );

        check_condition(
            "Frame switch moved top pointer to next-frame first row",
            top_idx == fill_idx
        );

        check_condition(
            "Padding is cleared after frame_switch",
            row_padding == {TB_INIT_ROWS{1'b0}}
        );


        //======================================================================
        // TEST 6
        // Fill first window of the next frame
        //======================================================================

        print_banner("TEST 6 - Next-frame initial fill");

        while (loaded_count < TB_INIT_ROWS)
            write_initial_row(
                fill_idx,
                occupied_count,
                loaded_count,
                top_idx
            );

        check_condition(
            "Next frame restarts processing after INIT_ROWS rows",
            (state == ST_RUN_BOTH) &
            (rows_loaded == TB_INIT_ROWS) &
            (occupied_rows == TB_INIT_ROWS)
        );

        next_frame_restart_covered = 1'b1;


        //======================================================================
        // TEST 7
        // Asynchronous reset during active integrated operation
        //======================================================================

        print_banner("TEST 7 - Asynchronous reset during active operation");

        // Synchronize before changing data_valid. During this edge the read
        // side advances once because RUN_BOTH is active.
        sync();

        data_valid = 1'b1;
        #1ps;

        check_controller(
            "Active operation before second reset",
            0,
            1,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_RUN_BOTH,
            loaded_count
        );

        sync();

        check_controller(
            "Both counters active before second reset",
            1,
            2,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_RUN_BOTH,
            loaded_count
        );

        // Runtime data change is made immediately after sync().
        data_valid = 1'b0;
        #1ps;

        // Assert reset asynchronously between clock edges.
        #(CLK_PERIOD / 4);

        resetb = 1'b0;
        #1ps;

        fill_idx       = 0;
        top_idx        = 0;
        occupied_count = 0;
        loaded_count   = 0;

        check_controller(
            "Asynchronous reset during active operation",
            0,
            0,
            fill_idx,
            top_idx,
            occupied_count,
            ZERO_MASK,
            ST_INIT_FILL,
            loaded_count
        );

        reset_during_activity_covered = 1'b1;

        // Release reset only after sync().
        sync();

        resetb = 1'b1;
        #1ps;

        check_controller(
            "Synchronized release after second reset",
            0,
            0,
            0,
            0,
            0,
            ZERO_MASK,
            ST_INIT_FILL,
            0
        );


        //======================================================================
        // TEST 8
        // Coverage verification
        //======================================================================

        print_banner("TEST 8 - Coverage verification");

        check_structural_coverage();

        check_condition(
            "Initial asynchronous reset covered",
            reset_covered
        );

        check_condition(
            "Asynchronous reset during activity covered",
            reset_during_activity_covered
        );

        check_condition(
            "Write pause covered",
            write_pause_covered
        );

        check_condition(
            "Parallel read/write activity covered",
            parallel_read_write_covered
        );

        check_condition(
            "Final-read BRAM drain covered",
            read_drain_covered
        );

        check_condition(
            "frame_done with row completion covered",
            frame_done_with_row_covered
        );

        check_condition(
            "Padding reservation covered",
            padding_reserved_covered
        );

        check_condition(
            "Final padded window covered",
            final_window_covered
        );

        check_condition(
            "frame_switch covered",
            frame_switch_covered
        );

        check_condition(
            "Next-frame restart covered",
            next_frame_restart_covered
        );

        check_condition(
            "ST_INIT_FILL covered",
            state_covered[ST_INIT_FILL]
        );

        check_condition(
            "ST_RUN_BOTH covered",
            state_covered[ST_RUN_BOTH]
        );

        check_condition(
            "ST_WAIT_WRITE covered",
            state_covered[ST_WAIT_WRITE]
        );

        check_condition(
            "ST_ADVANCE_WINDOW covered",
            state_covered[ST_ADVANCE_WINDOW]
        );

        check_condition(
            "ST_FRAME_SWITCH covered",
            state_covered[ST_FRAME_SWITCH]
        );


        //======================================================================
        // Final Summary
        //======================================================================

        $display("");
        $display("================================================================");
        $display("TEST SUMMARY");
        $display("================================================================");
        $display("Checks performed : %0d", check_count);
        $display("Errors           : %0d", error_count);
        $display("================================================================");

        if (error_count == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED with %0d error(s)", error_count);

        #10;
        $stop;
    end

endmodule
