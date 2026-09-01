//==============================================================================
/*
  Module Name : buffer_control

  Description :
    Controls the circular mapping and activation of the physical row buffers.

    This module contains control logic only. It does not receive or route pixel data.

    Responsibilities:
      1) Track the physical buffer currently used for writing.
         - fill_buffer_onehot identifies the BRAM receiving the incoming row.
         - It advances after row_write_done.
         - At frame_done, PAD_ROWS logical padding slots are reserved and the
           fill pointer skips over them before writing the next frame.

      2) Track the physical buffer corresponding to logical row 0.
         - top_buffer_onehot identifies the first physical BRAM of the active
           processing window.
         - It advances after advance_window.
         - At frame_switch, it moves directly to the first row of the next frame.

      3) Generate one-hot selectors for all logical rows in the active window.
         - row_sel[0] corresponds to logical row 0.
         - Each following row_sel entry selects the next physical BRAM in
           circular order.

      4) Track logical padding rows.
         - Padding rows are reserved logically and are not physically written.
         - padding_mask marks the PAD_ROWS physical slots reserved as padding.
         - row_padding tells the downstream mux which logical rows must be zero.

      5) Track the number of occupied logical row slots.
         - Completed real rows and reserved padding rows increase occupancy.
         - Released rows decrease occupancy.
         - The occupancy generates next_row_ready and write_blocked.

      6) Generate the physical BRAM write enables.
         - When wr_valid is asserted, only the current fill buffer is enabled
           for writing.

      7) Generate the physical BRAM read enables.
         - When rd_valid is asserted, all physical BRAMs belonging to the
           active processing window are enabled for reading.

    Example for NUM_BUFFERS = 8 and INIT_ROWS = 5:

      top_buffer_onehot = 8'b01000000

        row_sel[0] = 8'b01000000   -> BRAM6
        row_sel[1] = 8'b10000000   -> BRAM7
        row_sel[2] = 8'b00000001   -> BRAM0
        row_sel[3] = 8'b00000010   -> BRAM1
        row_sel[4] = 8'b00000100   -> BRAM2

    This allows the logical processing window to move circularly across the
    physical row buffers without moving the stored pixel data itself.

    No pixel data enters or leaves this module.
*/
//==============================================================================

module buffer_control #(
    parameter int NUM_BUFFERS = 16,
    parameter int INIT_ROWS   = 5,
    parameter int STRIDE      = 3,
    parameter int OCC_CNT_W   = 5
)(
    input  logic                     clk,                    // System clock
    input  logic                     resetb,                 // Asynchronous active-low reset

    input  logic                     row_write_done,         // Current real input row was fully written
    input  logic                     advance_window,         // Advance the active processing window by STRIDE rows
    input  logic                     frame_done,             // End of real rows for the current incoming frame
    input  logic                     frame_switch,           // Move from final padded window to next frame

    input  logic                     wr_valid,               // Valid BRAM write operation
    input  logic                     rd_valid,               // Valid BRAM read operation

    output logic                     next_row_ready,         // Next STRIDE-row processing window is available
    output logic                     write_blocked,          // Real-row writing must stop to preserve padding margin
    output logic                     last_window,            // Current window is the final output group of the frame

    output logic [NUM_BUFFERS-1:0]   bram_wr_en,             // Write enable for each physical BRAM
    output logic [NUM_BUFFERS-1:0]   bram_rd_en,             // Read enable for each physical BRAM

    output logic [NUM_BUFFERS-1:0]   row_sel [0:INIT_ROWS-1],// Physical BRAM selected for each logical row
    output logic [INIT_ROWS-1:0]     row_padding             // Logical rows that must be supplied as zero
);


    localparam int PAD_ROWS = STRIDE - 1;

    localparam logic [NUM_BUFFERS-1:0] FIRST_BUFFER_ONEHOT =
        {{(NUM_BUFFERS-1){1'b0}}, 1'b1};


    logic [NUM_BUFFERS-1:0] fill_buffer_onehot; // Physical BRAM currently used for writing
    logic [NUM_BUFFERS-1:0] top_buffer_onehot;  // Physical BRAM corresponding to logical row 0
    logic [NUM_BUFFERS-1:0] padding_mask;       // Physical slots reserved as logical padding
    logic [NUM_BUFFERS-1:0] active_read_mask;   // Physical BRAMs belonging to the active window
    logic [NUM_BUFFERS-1:0] next_frame_start_onehot; // First physical slot of the next frame
    logic                   frame_boundary_valid;    // frame_done boundary is currently active
    logic [NUM_BUFFERS-1:0] boundary_cursor;         // Used to detect the final STRIDE output group

    logic [OCC_CNT_W-1:0]   occupied_rows;      // Number of occupied real or padding row slots
    logic [OCC_CNT_W-1:0]   occupied_rows_next;
    logic [OCC_CNT_W-1:0]   frame_release_rows; // Old-frame slots released at frame_switch

    integer row_idx;
    integer padding_row_idx;
    integer pad_idx;
    integer mask_idx;
    integer frame_row_idx;
    integer boundary_idx;


    //--------------------------------------------------------------------------
    // Fill-buffer pointer
    //
    // Advances whenever one complete incoming row has been written.
    // At frame_done, PAD_ROWS slots are skipped before writing the next frame.
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge resetb) begin

        if (~resetb)
            fill_buffer_onehot <= FIRST_BUFFER_ONEHOT;

        else begin
            case ({frame_done, row_write_done})

                2'b01:
                    fill_buffer_onehot <= {
                        fill_buffer_onehot[NUM_BUFFERS-2:0],
                        fill_buffer_onehot[NUM_BUFFERS-1]
                    };

                2'b10:
                    fill_buffer_onehot <= {
                        fill_buffer_onehot[NUM_BUFFERS-PAD_ROWS-1:0],
                        fill_buffer_onehot[NUM_BUFFERS-1:NUM_BUFFERS-PAD_ROWS]
                    };

                2'b11:
                    fill_buffer_onehot <= {
                        fill_buffer_onehot[NUM_BUFFERS-PAD_ROWS-2:0],
                        fill_buffer_onehot[NUM_BUFFERS-1:NUM_BUFFERS-PAD_ROWS-1]
                    };

                default:
                    fill_buffer_onehot <= fill_buffer_onehot;

            endcase
        end

    end


    //--------------------------------------------------------------------------
    // Next-frame start pointer
    //
    // Captures the first physical slot after the reserved padding region.
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge resetb) begin

        if (~resetb)
            next_frame_start_onehot <= FIRST_BUFFER_ONEHOT;

        else if (frame_done) begin

            if (row_write_done)
                next_frame_start_onehot <= {
                    fill_buffer_onehot[NUM_BUFFERS-PAD_ROWS-2:0],
                    fill_buffer_onehot[NUM_BUFFERS-1:NUM_BUFFERS-PAD_ROWS-1]
                };
            else
                next_frame_start_onehot <= {
                    fill_buffer_onehot[NUM_BUFFERS-PAD_ROWS-1:0],
                    fill_buffer_onehot[NUM_BUFFERS-1:NUM_BUFFERS-PAD_ROWS]
                };

        end

    end


    //--------------------------------------------------------------------------
    // Frame-boundary validity
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge resetb) begin

        if (~resetb)
            frame_boundary_valid <= 1'b0;

        else if (frame_done)
            frame_boundary_valid <= 1'b1;

        else if (frame_switch)
            frame_boundary_valid <= 1'b0;

    end


    //--------------------------------------------------------------------------
    // Top-buffer pointer
    //
    // Advances only when the complete processing window is allowed to move.
    // Normal movement advances by STRIDE rows. At frame_switch, it moves to
    // the first physical slot of the next frame.
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge resetb) begin

        if (~resetb)
            top_buffer_onehot <= FIRST_BUFFER_ONEHOT;

        else if (frame_switch)
            top_buffer_onehot <= next_frame_start_onehot;

        else if (advance_window)
            top_buffer_onehot <= {
                top_buffer_onehot[NUM_BUFFERS-STRIDE-1:0],
                top_buffer_onehot[NUM_BUFFERS-1:NUM_BUFFERS-STRIDE]
            };

    end


    //--------------------------------------------------------------------------
    // Active row selectors
    //
    // row_sel[0] is the current top buffer. Each following logical row selects
    // the next physical BRAM in circular order.
    //--------------------------------------------------------------------------

    always_comb begin

        row_sel[0] = top_buffer_onehot;

        for (row_idx = 1; row_idx < INIT_ROWS; row_idx = row_idx + 1) begin

            row_sel[row_idx] = {
                row_sel[row_idx-1][NUM_BUFFERS-2:0],
                row_sel[row_idx-1][NUM_BUFFERS-1]
            };

        end

    end


    //--------------------------------------------------------------------------
    // Final-window detection
    //
    // HPS already supplies the one-pixel image border, including the bottom
    // zero row. The FPGA reserves only STRIDE-1 additional logical rows.
    // Depending on image height, the final active window therefore contains
    // zero, one, or two logical padding rows.
    //--------------------------------------------------------------------------

    always_comb begin

        last_window = 1'b0;

        boundary_cursor = {
            row_sel[INIT_ROWS-1][NUM_BUFFERS-2:0],
            row_sel[INIT_ROWS-1][NUM_BUFFERS-1]
        };

        for (boundary_idx = 0; boundary_idx < STRIDE; boundary_idx = boundary_idx + 1) begin

            if (frame_boundary_valid &&
                (boundary_cursor == next_frame_start_onehot))
                last_window = 1'b1;

            boundary_cursor = {
                boundary_cursor[NUM_BUFFERS-2:0],
                boundary_cursor[NUM_BUFFERS-1]
            };

        end

    end


    //--------------------------------------------------------------------------
    // Padding mask
    //
    // At frame_done, PAD_ROWS consecutive physical slots are marked as padding.
    // The mask is built by circular shifts and remains valid until frame_switch.
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge resetb) begin : padding_mask_update
        logic [NUM_BUFFERS-1:0] padding_temp;

        if (~resetb)
            padding_mask <= {NUM_BUFFERS{1'b0}};

        else if (frame_done) begin

            if (row_write_done)
                padding_temp = {
                    fill_buffer_onehot[NUM_BUFFERS-2:0],
                    fill_buffer_onehot[NUM_BUFFERS-1]
                };
            else
                padding_temp = fill_buffer_onehot;

            for (pad_idx = 1; pad_idx < PAD_ROWS; pad_idx = pad_idx + 1)
                padding_temp = padding_temp |
                    {
                        padding_temp[NUM_BUFFERS-2:0],
                        padding_temp[NUM_BUFFERS-1]
                    };

            padding_mask <= padding_temp;
        end

        else if (frame_switch)
            padding_mask <= {NUM_BUFFERS{1'b0}};

    end


    //--------------------------------------------------------------------------
    // Logical padding indication
    //
    // A logical row is padding when its selected physical BRAM is marked in
    // padding_mask.
    //--------------------------------------------------------------------------

    always_comb begin

        row_padding = {INIT_ROWS{1'b0}};

        for (padding_row_idx = 0; padding_row_idx < INIT_ROWS; padding_row_idx = padding_row_idx + 1)
            row_padding[padding_row_idx] = |(row_sel[padding_row_idx] & padding_mask);

    end


    //--------------------------------------------------------------------------
    // Frame-switch release count
    //
    // The final active window may contain zero, one, or two logical tail-
    // padding rows. Release the remaining frame rows together with the reserved
    // padding slots.
    //--------------------------------------------------------------------------

    always_comb begin

        frame_release_rows = PAD_ROWS;

        for (frame_row_idx = 0; frame_row_idx < INIT_ROWS; frame_row_idx = frame_row_idx + 1)
            if (~row_padding[frame_row_idx])
                frame_release_rows = frame_release_rows + 1'b1;

    end


    //--------------------------------------------------------------------------
    // Occupied-row tracking
    //
    // Real rows and logical padding rows occupy circular-buffer slots.
    // All simultaneous occupancy-changing events are handled explicitly.
    //--------------------------------------------------------------------------

    always_comb begin

        occupied_rows_next = occupied_rows;

        case ({frame_done, row_write_done, advance_window, frame_switch})

            4'b0000:
                occupied_rows_next = occupied_rows;

            4'b0001:
                occupied_rows_next = occupied_rows - frame_release_rows;

            4'b0010:
                occupied_rows_next = occupied_rows - STRIDE;

            4'b0011:
                occupied_rows_next = occupied_rows - frame_release_rows - STRIDE;

            4'b0100:
                occupied_rows_next = occupied_rows + 1'b1;

            4'b0101:
                occupied_rows_next = occupied_rows + 1'b1 - frame_release_rows;

            4'b0110:
                occupied_rows_next = occupied_rows + 1'b1 - STRIDE;

            4'b0111:
                occupied_rows_next = occupied_rows + 1'b1 - frame_release_rows - STRIDE;

            4'b1000:
                occupied_rows_next = occupied_rows + PAD_ROWS;

            4'b1001:
                occupied_rows_next = occupied_rows + PAD_ROWS - frame_release_rows;

            4'b1010:
                occupied_rows_next = occupied_rows + PAD_ROWS - STRIDE;

            4'b1011:
                occupied_rows_next = occupied_rows + PAD_ROWS - frame_release_rows - STRIDE;

            4'b1100:
                occupied_rows_next = occupied_rows + PAD_ROWS + 1'b1;

            4'b1101:
                occupied_rows_next = occupied_rows + PAD_ROWS + 1'b1 - frame_release_rows;

            4'b1110:
                occupied_rows_next = occupied_rows + PAD_ROWS + 1'b1 - STRIDE;

            4'b1111:
                occupied_rows_next = occupied_rows + PAD_ROWS + 1'b1 - frame_release_rows - STRIDE;

            default:
                occupied_rows_next = occupied_rows;

        endcase

    end


    always_ff @(posedge clk or negedge resetb) begin

        if (~resetb)
            occupied_rows <= {OCC_CNT_W{1'b0}};

        else
            occupied_rows <= occupied_rows_next;

    end


    // The next processing window is available when STRIDE additional logical
    // rows exist beyond the current active window.
    assign next_row_ready =
        (occupied_rows >= (INIT_ROWS + STRIDE));


    // Keep PAD_ROWS slots free so end-of-frame padding can always be reserved.
    assign write_blocked =
        (occupied_rows >= (NUM_BUFFERS - PAD_ROWS));


    // Enable writing only to the current fill buffer when a valid write occurs.
    assign bram_wr_en =
        fill_buffer_onehot &
        {NUM_BUFFERS{wr_valid}};


    //--------------------------------------------------------------------------
    // Active read mask
    //
    // Combines all logical-row selectors into one mask containing every
    // physical BRAM that belongs to the current processing window.
    //--------------------------------------------------------------------------

    always_comb begin

        active_read_mask = {NUM_BUFFERS{1'b0}};

        for (mask_idx = 0; mask_idx < INIT_ROWS; mask_idx = mask_idx + 1)
            active_read_mask = active_read_mask | row_sel[mask_idx];

    end


    // Enable all active-window BRAMs when a valid read operation occurs.
    assign bram_rd_en =
        active_read_mask &
        {NUM_BUFFERS{rd_valid}};


endmodule
