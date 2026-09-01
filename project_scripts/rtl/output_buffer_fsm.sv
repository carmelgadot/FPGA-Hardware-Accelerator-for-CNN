/*==============================================================================
  Module: output_buffer_fsm
  Purpose:
    Controls ping-pong operation of two output-buffer groups.

    The output-buffer memory is organized as two groups. Each group contains
    PARALLEL_OUTPUTS physical BRAMs and stores one complete set of parallel
    convolution-output rows.

    The FSM separates group management from address generation and BRAM timing:
      - write_done indicates that the active write group is completely full.
      - read_done indicates that the active read group has completely finished
        its read operation and may safely be reused for writing.
      - Address counters and BRAM read-latency handling are implemented in the
        output_buffer_controller, not in this FSM.


    Separate write-only and wait-read states are kept explicitly so it is easy
    to observe which side finished first during simulation and on-chip debug.

  
  Reset behavior:
    - state returns asynchronously to ST_FILL_GROUP0.
    - group 0 is enabled for the initial fill.
    - no read operation is enabled until group 0 is full.
==============================================================================*/

module output_buffer_fsm (
    input  logic clk,               // System clock
    input  logic resetb,            // Asynchronous active-low reset

    input  logic write_done,        // Active write group is completely full
    input  logic read_done,         // Active read group is completely finished

    output logic en_write,          // Enables writing to the selected write group
    output logic en_read,           // Enables reading from the selected read group
    output logic write_group_sel,   // 0: group 0, 1: group 1
    output logic read_group_sel     // 0: group 0, 1: group 1
);

  //--------------------------------------------------------------------------
  // State encoding
  //--------------------------------------------------------------------------
  localparam logic [2:0]
      ST_FILL_GROUP0  = 3'd0,
      ST_WRITE1_READ0 = 3'd1,
      ST_WRITE1_ONLY  = 3'd2,
      ST_WAIT_READ0   = 3'd3,
      ST_WRITE0_READ1 = 3'd4,
      ST_WRITE0_ONLY  = 3'd5,
      ST_WAIT_READ1   = 3'd6;

  logic [2:0] state;       // Current FSM state
  logic [2:0] next_state;  // Next FSM state


  //--------------------------------------------------------------------------
  // State register
  //--------------------------------------------------------------------------
  always_ff @(posedge clk or negedge resetb) begin
    if (~resetb)
      state <= ST_FILL_GROUP0;
    else
      state <= next_state;
  end


  //--------------------------------------------------------------------------
  // Next-state logic
  //--------------------------------------------------------------------------
  always_comb begin
    next_state = state;

    case (state)

      // Initial operation: fill group 0 before any output-buffer read starts.
      ST_FILL_GROUP0: begin
        case (write_done)
          1'b1:    next_state = ST_WRITE1_READ0;
          default: next_state = ST_FILL_GROUP0;
        endcase
      end


      // Normal phase: fill group 1 while group 0 is being read.
      ST_WRITE1_READ0: begin
        case ({write_done, read_done})
          2'b01:   next_state = ST_WRITE1_ONLY;
          2'b10:   next_state = ST_WAIT_READ0;
          2'b11:   next_state = ST_WRITE0_READ1;
          default: next_state = ST_WRITE1_READ0;
        endcase
      end


      // Group 0 finished reading first. Continue filling group 1.
      ST_WRITE1_ONLY: begin
        case (write_done)
          1'b1:    next_state = ST_WRITE0_READ1;
          default: next_state = ST_WRITE1_ONLY;
        endcase
      end


      // Group 1 filled first. Wait until group 0 is completely read.
      ST_WAIT_READ0: begin
        case (read_done)
          1'b1:    next_state = ST_WRITE0_READ1;
          default: next_state = ST_WAIT_READ0;
        endcase
      end


      // Normal phase: fill group 0 while group 1 is being read.
      ST_WRITE0_READ1: begin
        case ({write_done, read_done})
          2'b01:   next_state = ST_WRITE0_ONLY;
          2'b10:   next_state = ST_WAIT_READ1;
          2'b11:   next_state = ST_WRITE1_READ0;
          default: next_state = ST_WRITE0_READ1;
        endcase
      end


      // Group 1 finished reading first. Continue filling group 0.
      ST_WRITE0_ONLY: begin
        case (write_done)
          1'b1:    next_state = ST_WRITE1_READ0;
          default: next_state = ST_WRITE0_ONLY;
        endcase
      end


      // Group 0 filled first. Wait until group 1 is completely read.
      ST_WAIT_READ1: begin
        case (read_done)
          1'b1:    next_state = ST_WRITE1_READ0;
          default: next_state = ST_WAIT_READ1;
        endcase
      end


      default: begin
        next_state = ST_FILL_GROUP0;
      end

    endcase
  end


  //--------------------------------------------------------------------------
  // Output logic
  //--------------------------------------------------------------------------
  always_comb begin
    case (state)

      ST_FILL_GROUP0: begin
        en_write        = 1'b1;
        en_read         = 1'b0;
        write_group_sel = 1'b0;
        read_group_sel  = 1'b0;
      end

      ST_WRITE1_READ0: begin
        en_write        = 1'b1;
        en_read         = 1'b1;
        write_group_sel = 1'b1;
        read_group_sel  = 1'b0;
      end

      ST_WRITE1_ONLY: begin
        en_write        = 1'b1;
        en_read         = 1'b0;
        write_group_sel = 1'b1;
        read_group_sel  = 1'b0;
      end

      ST_WAIT_READ0: begin
        en_write        = 1'b0;
        en_read         = 1'b1;
        write_group_sel = 1'b1;
        read_group_sel  = 1'b0;
      end

      ST_WRITE0_READ1: begin
        en_write        = 1'b1;
        en_read         = 1'b1;
        write_group_sel = 1'b0;
        read_group_sel  = 1'b1;
      end

      ST_WRITE0_ONLY: begin
        en_write        = 1'b1;
        en_read         = 1'b0;
        write_group_sel = 1'b0;
        read_group_sel  = 1'b1;
      end

      ST_WAIT_READ1: begin
        en_write        = 1'b0;
        en_read         = 1'b1;
        write_group_sel = 1'b0;
        read_group_sel  = 1'b1;
      end

      default: begin
        en_write        = 1'b0;
        en_read         = 1'b0;
        write_group_sel = 1'b0;
        read_group_sel  = 1'b0;
      end

    endcase
  end

endmodule
