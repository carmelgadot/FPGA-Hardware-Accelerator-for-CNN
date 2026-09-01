/*==============================================================================
  Module: window_manager_fsm
  Purpose:
    Controls the write/read flow of a circular row-buffer system used to build
    a vertical sliding window for convolution processing.

  Architecture overview:
    - The physical row buffers form a circular queue of rows. Real camera rows
      are written in order, while the processing side reads INIT_ROWS logical
      rows as the active convolution window.
    - The writer and the processing side are allowed to run at different rates.
      The writer may continue several rows ahead as long as enough safe buffer
      space remains. The processing side may continue advancing as long as the
      next logical row required by the window already exists.
    - A protected free-buffer margin is kept between the writer and rows that
      are still needed by processing. This prevents the writer from overwriting
      unread data and guarantees room for end-of-frame padding.
    - End-of-frame padding is represented by reserved logical row slots rather
      than real camera rows. External buffer/mux logic marks these slots as
      padding and supplies zeros whenever such a logical row is selected.
      Therefore the convolution unit sees the required zero rows without
      physically writing full zero rows into memory.
    - The active window is read column by column. For each column address, one
      pixel is read from each of the INIT_ROWS logical rows and these pixels are
      supplied together to the convolution processing unit. After all columns
      of the current window are read, the controller may advance to the next window.
    - frame_done marks the end of the real rows of the current incoming frame.
      The FSM does not count the full image height. It only counts up to
      INIT_ROWS real rows of the next frame so processing can start as soon as
      the first complete convolution window of that frame is available.

  External buffer-management logic is responsible for:
    - tracking the fill and top buffer positions
    - tracking occupied logical rows and protected free space
    - marking reserved padding-row slots
    - mapping logical window rows to physical row buffers
    - generating next_row_ready, write_blocked and last_window

  This FSM is responsible for:
    - enabling real-row writing when buffer space is safe
    - enabling column-by-column reading of the active convolution window
    - waiting for writing when the processing side runs ahead
    - waiting for processing when the writer reaches the protected margin
    - issuing a one-cycle advance_window pulse for a normal window advance
    - issuing a one-cycle frame_switch pulse after the final output group

  State behavior:
    - ST_INIT_FILL:
        Write real rows and wait until INIT_ROWS rows of the frame are ready.
        Reading into the convolution unit is disabled.

    - ST_RUN_BOTH:
        Normal operation. Real-row writing and active-window reading are both
        enabled, subject to the external write_blocked condition.

    - ST_WAIT_WRITE:
        The current window has finished reading, but the next logical row is not
        ready yet. Reading stops while writing continues.

    - ST_WAIT_PROCESS:
        The writer has reached the protected buffer margin. Writing stops while
        active-window reading continues so old rows can be released.

    - ST_ADVANCE_WINDOW:
        One-cycle state that advances to the next active processing window.

    - ST_FRAME_SWITCH:
        One-cycle state entered after the final output group of a frame has
        finished. The external buffer-management logic switches directly to the
        first real row of the next frame. If INIT_ROWS rows of that frame are
        already available, processing resumes immediately; otherwise the FSM
        returns to ST_INIT_FILL.

  Reset behavior:
    - state       returns to ST_INIT_FILL
    - rows_loaded returns to zero
==============================================================================*/

module window_manager_fsm #(
    parameter int ROW_CNT_W = 3,
    // Number of real rows needed to make a processing window valid
    parameter int INIT_ROWS = 5
)(
    input  logic clk,                 // System clock
    input  logic resetb,              // Asynchronous active-low reset

    input  logic row_write_done,      // One complete real input row was written
    input  logic process_done,        // Current convolution-window scan completed
    input  logic frame_done,          // End of real input rows for the current frame

    input  logic next_row_ready,      // Next logical row required for window advance is ready
    input  logic write_blocked,       // Real-row writing must stop to preserve the safe margin
    input  logic last_window,         // Current window is the final output group of the frame

    output logic en_write_row,        // Enables writing of real input rows
    output logic en_process_window,   // Enables reading window columns into the convolution unit
    output logic advance_window,      // One-cycle pulse to advance to the next window
    output logic frame_switch         // One-cycle pulse to switch to the next frame
);

  //--------------------------------------------------------------------------
  // State encoding
  //--------------------------------------------------------------------------
  localparam logic [2:0]
      ST_INIT_FILL      = 3'd0,
      ST_RUN_BOTH       = 3'd1,
      ST_WAIT_WRITE     = 3'd2,
      ST_WAIT_PROCESS   = 3'd3,
      ST_ADVANCE_WINDOW = 3'd4,
      ST_FRAME_SWITCH   = 3'd5;

  logic [2:0] state;                         // Current FSM state
  logic [2:0] next_state;                    // Next FSM state

  logic [ROW_CNT_W-1:0] rows_loaded;          // Number of real rows accumulated for the incoming frame
  logic                 rows_loaded_en;       // Enables incrementing rows_loaded on a completed real row
  logic                 rows_done;            // Pulses when the INIT_ROWS-th real row is completed


  //--------------------------------------------------------------------------
  // Incoming-frame row counter control
  //
  // Count real rows regardless of the current FSM state. This allows rows of
  // the next frame to accumulate while the previous frame is still being
  // processed. The counter saturates at INIT_ROWS and is cleared by frame_done.
  //--------------------------------------------------------------------------
  assign rows_loaded_en = row_write_done &
                          (rows_loaded < INIT_ROWS);

  //--------------------------------------------------------------------------
  // rows_done generation
  // Asserted when the current row_write_done completes INIT_ROWS real rows.
  //--------------------------------------------------------------------------
  assign rows_done = row_write_done &
                     (rows_loaded == (INIT_ROWS - 1));

  //--------------------------------------------------------------------------
  // External counter instance
  //--------------------------------------------------------------------------
  counter #(
      .WIDTH(ROW_CNT_W)
  ) u_rows_loaded_counter (
      .clk    (clk),
      .resetb (resetb),
      .en     (rows_loaded_en),
      .clr    (frame_done),
      .count  (rows_loaded)
  );


  //--------------------------------------------------------------------------
  // State register
  //--------------------------------------------------------------------------
  always_ff @(posedge clk or negedge resetb) begin
    if (~resetb)
      state <= ST_INIT_FILL;
    else
      state <= next_state;
  end


  //--------------------------------------------------------------------------
  // Next-state logic
  //
  // Relevant 0/1 input combinations are grouped explicitly in each state.
  // The default branch covers all remaining combinations so next_state is
  // always defined and no input combination is left unspecified.
  //--------------------------------------------------------------------------
  always_comb begin
    next_state = state;

    case (state)

      // Wait until INIT_ROWS real rows of the frame being filled are ready.
      ST_INIT_FILL: begin
        case ({rows_done, (rows_loaded == INIT_ROWS)})
          2'b01,
          2'b10,
          2'b11:   next_state = ST_RUN_BOTH;
          default: next_state = ST_INIT_FILL;
        endcase
      end


      // Normal operation. A completed window scan has priority over a blocked
      // writer because the controller must first decide whether to finish the
      // frame, advance the window, or wait for another logical row.
      ST_RUN_BOTH: begin
        case ({process_done, last_window, next_row_ready, write_blocked})
          // Current window is complete and is the final output group.
          4'b1100,
          4'b1101,
          4'b1110,
          4'b1111: next_state = ST_FRAME_SWITCH;

          // Current window is complete and the next logical row is ready.
          4'b1010,
          4'b1011: next_state = ST_ADVANCE_WINDOW;

          // Current window is complete but the next logical row is not ready.
          4'b1000,
          4'b1001: next_state = ST_WAIT_WRITE;

          // Processing is still running, but writing reached the safe margin.
          4'b0001,
          4'b0011,
          4'b0101,
          4'b0111: next_state = ST_WAIT_PROCESS;

          // All other combinations keep normal operation running.
          default: next_state = ST_RUN_BOTH;
        endcase
      end


      // Processing is already complete. A frame boundary may become known
      // while waiting, so a newly detected final window has priority over a
      // normal advance.
      ST_WAIT_WRITE: begin
        case ({last_window, next_row_ready})
          2'b10,
          2'b11:   next_state = ST_FRAME_SWITCH;
          2'b01:   next_state = ST_ADVANCE_WINDOW;
          default: next_state = ST_WAIT_WRITE;
        endcase
      end


      // Writing is blocked. Continue reading the active window until the
      // current scan completes. Then finish the frame, advance, or wait for a
      // logical row according to the available buffer information.
      ST_WAIT_PROCESS: begin
        case ({process_done, last_window, next_row_ready})
          3'b110,
          3'b111:  next_state = ST_FRAME_SWITCH;

          3'b101:  next_state = ST_ADVANCE_WINDOW;

          3'b100:  next_state = ST_WAIT_WRITE;

          default: next_state = ST_WAIT_PROCESS;
        endcase
      end


      // One-cycle pulse state for a normal one-row window advance.
      ST_ADVANCE_WINDOW: begin
        next_state = ST_RUN_BOTH;
      end


      // One-cycle pulse state for moving from the completed frame to the next
      // frame. Rows of the next frame may already have been written.
      ST_FRAME_SWITCH: begin
        case ({rows_done, (rows_loaded == INIT_ROWS)})
          2'b01,
          2'b10,
          2'b11:   next_state = ST_RUN_BOTH;
          default: next_state = ST_INIT_FILL;
        endcase
      end


      default: begin
        next_state = ST_INIT_FILL;
      end

    endcase
  end


  //--------------------------------------------------------------------------
  // Output logic
  //--------------------------------------------------------------------------
  always_comb begin
    case (state)

      ST_INIT_FILL: begin
        en_write_row      = ~write_blocked;
        en_process_window = 1'b0;
        advance_window    = 1'b0;
        frame_switch      = 1'b0;
      end

      ST_RUN_BOTH: begin
        en_write_row      = ~write_blocked;
        en_process_window = 1'b1;
        advance_window    = 1'b0;
        frame_switch      = 1'b0;
      end

      ST_WAIT_WRITE: begin
        en_write_row      = ~write_blocked;
        en_process_window = 1'b0;
        advance_window    = 1'b0;
        frame_switch      = 1'b0;
      end

      ST_WAIT_PROCESS: begin
        en_write_row      = 1'b0;
        en_process_window = 1'b1;
        advance_window    = 1'b0;
        frame_switch      = 1'b0;
      end

      ST_ADVANCE_WINDOW: begin
        en_write_row      = ~write_blocked;
        en_process_window = 1'b0;
        advance_window    = 1'b1;
        frame_switch      = 1'b0;
      end

      ST_FRAME_SWITCH: begin
        en_write_row      = ~write_blocked;
        en_process_window = 1'b0;
        advance_window    = 1'b0;
        frame_switch      = 1'b1;
      end

      default: begin
        en_write_row      = 1'b0;
        en_process_window = 1'b0;
        advance_window    = 1'b0;
        frame_switch      = 1'b0;
      end

    endcase
  end

endmodule
