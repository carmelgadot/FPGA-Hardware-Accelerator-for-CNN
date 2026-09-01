//==============================================================================
/*
  Module Name : row_buffer_controller

  Description :
    Top-level control module for the circular row-buffer system.

    This module contains control logic only. 
    No pixel data passes through this module.

    Internal modules:
      1) window_manager_fsm
         - Controls the high-level system sequence:
             * Initial row filling
             * Simultaneous write and processing
             * Waiting for write completion
             * Waiting for processing completion
             * Advancing the processing window
             * Switching between frames

      2) Write address counter
         - Generates the write address inside the current row.
         - Advances only when writing is enabled and input data is valid.
         - Clears after the final pixel of the row is written.

      3) Read address counter
         - Generates the common read address for the active row buffers.
         - Advances while window processing is enabled.
         - Clears after the final read address is issued.

      4) buffer_control
         - Tracks the current fill buffer.
         - Tracks the top buffer of the active processing window.
         - Tracks occupied row slots and end-of-frame padding slots.
         - Generates the active logical-row selectors and padding indication.
         - Generates the write enable for each physical BRAM.
         - Generates the read enable for each physical BRAM.

        No feedback is required from the processing pipeline. Once the
        data has been read and forwarded to the pipeline, the controller
        considers the processing scan complete.


*/
//==============================================================================

module row_buffer_controller #(
    parameter int ROW_LENGTH  = 640,
    parameter int ADDR_WIDTH  = 10,
    parameter int ROW_CNT_W   = 3,
    parameter int INIT_ROWS   = 5,
    parameter int STRIDE      = 3,
    parameter int NUM_BUFFERS = 16,
    parameter int OCC_CNT_W   = 5
)(
    input  logic                     clk,                    // System clock
    input  logic                     resetb,                 // Asynchronous active-low reset
    input  logic                     data_valid,             // Incoming pixel is valid
    input  logic                     frame_done,             // End of real rows for the current incoming frame

    output logic [ADDR_WIDTH-1:0]    wr_addr,                // Current BRAM write address
    output logic [ADDR_WIDTH-1:0]    rd_addr,                // Current BRAM read address

    output logic [NUM_BUFFERS-1:0]   bram_wr_en,             // Write enable for each physical BRAM
    output logic [NUM_BUFFERS-1:0]   bram_rd_en,             // Read enable for each physical BRAM

    output logic [NUM_BUFFERS-1:0]   row_sel [0:INIT_ROWS-1],// Physical BRAM selected for each logical row
    output logic [INIT_ROWS-1:0]     row_padding             // Logical rows that must be supplied as zero
);


    logic en_write_row;          // Enables writing of the current input row
    logic en_process_window;     // Enables reading of the current processing window
    logic advance_window;        // Advances the logical processing window by STRIDE rows
    logic frame_switch;          // Switches from the final output group to the next frame

    logic next_row_ready;        // Another logical row exists after the active window
    logic write_blocked;         // Protected free-buffer margin has been reached
    logic last_window;           // Active window is the final output group of the frame

    logic wr_valid;              // Valid BRAM write operation
    logic rd_valid;              // Valid BRAM read request

    logic row_write_done;        // Last pixel of the current row was written
    logic last_read_issued;      // Final BRAM read request of the current window was issued
    logic read_pending;          // Final BRAM read is propagating through the registered BRAM output
    logic process_done;          // Final BRAM read has propagated and the window scan is complete


    //==========================================================================
    // Window Manager FSM
    //
    // Controls the high-level sequence of the row-buffer system.
    // It decides when row writing and window processing are enabled, waits for
    // both operations to complete, and generates advance_window when the
    // active processing window can move to the next set of rows.
    //==========================================================================

    window_manager_fsm #(
        .ROW_CNT_W (ROW_CNT_W),
        .INIT_ROWS (INIT_ROWS)
    ) u_window_manager_fsm (
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


    // A write occurs only when the FSM enables writing and input data is valid.
    assign wr_valid = en_write_row && data_valid;

    // Assert when the last valid pixel of the current row is written.
    assign row_write_done =
        wr_valid &&
        (wr_addr == ROW_LENGTH-1);


    //==========================================================================
    // Write Address Counter
    //
    // Generates the address used for writing the incoming row into the BRAM.
    // The counter advances only for an actual valid write and returns to zero
    // after the final pixel of the current row has been written.
    //==========================================================================

    counter #(
        .WIDTH (ADDR_WIDTH)
    ) u_wr_address_counter (
        .clk    (clk),
        .resetb (resetb),
        .en     (wr_valid),
        .clr    (row_write_done),
        .count  (wr_addr)
    );


    // A BRAM read request is issued only while window processing is enabled
    // and the final read of the current scan is not still propagating.
    assign rd_valid = en_process_window && ~read_pending;

    // Assert when the final read address of the current window is issued.
    assign last_read_issued =
        rd_valid &&
        (rd_addr == ROW_LENGTH-1);

    // Keep the active row mapping unchanged for one additional cycle after the
    // final read request so the registered BRAM output can propagate safely.
    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb)
            read_pending <= 1'b0;
        else
            read_pending <= last_read_issued;
    end

    // Processing completes after the final BRAM read has propagated.
    assign process_done = read_pending;


    //==========================================================================
    // Read Address Counter
    //
    // Generates the common read address used by all active row buffers.
    // The counter advances only for a valid BRAM read request and returns to
    // zero after the final address of the current window scan is issued.
    //==========================================================================

    counter #(
        .WIDTH (ADDR_WIDTH)
    ) u_rd_address_counter (
        .clk    (clk),
        .resetb (resetb),
        .en     (rd_valid),
        .clr    (last_read_issued),
        .count  (rd_addr)
    );


    //==========================================================================
    // Buffer Control
    //
    // Manages the circular mapping between logical rows and physical BRAMs.
    // It tracks the buffer currently used for writing and the first buffer of
    // the active processing window. Based on these positions and the current
    // read/write valid signals, it generates the BRAM read/write enables and
    // the logical-row selectors used by the row-buffer data path.
    //==========================================================================

    buffer_control #(
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS),
        .STRIDE      (STRIDE),
        .OCC_CNT_W   (OCC_CNT_W)
    ) u_buffer_control (
        .clk            (clk),
        .resetb         (resetb),

        .row_write_done (row_write_done),
        .advance_window (advance_window),
        .frame_done     (frame_done),
        .frame_switch   (frame_switch),

        .wr_valid       (wr_valid),
        .rd_valid       (rd_valid),

        .next_row_ready (next_row_ready),
        .write_blocked  (write_blocked),
        .last_window    (last_window),

        .bram_wr_en     (bram_wr_en),
        .bram_rd_en     (bram_rd_en),

        .row_sel        (row_sel),
        .row_padding    (row_padding)
    );


endmodule