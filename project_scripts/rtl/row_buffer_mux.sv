//==============================================================================
/*
  Module Name : row_buffer_mux.sv 

 Description :
    The system contains NUM_BUFFERS physical BRAMs, while only INIT_ROWS
    belong to the current processing window.

    A logical row represents the position of a row inside the active window,
    independently of the physical BRAM in which it is stored.

    row_buffer_mux maps each logical row to its corresponding physical BRAM
    according to its one-hot row_sel selector.  
   Exactly one bit should be active in row_sel.
   The active bit selects the physical BRAM assigned to that row.

    For example, for a 5-row processing window:

        logical row 0 = first  row of the current window
        logical row 1 = second row of the current window
        logical row 2 = third  row of the current window
        logical row 3 = fourth row of the current window
        logical row 4 = fifth  row of the current window

    Because the physical BRAMs are used circularly, a logical row is not
    permanently associated with a specific physical BRAM.

    Example:

        Assume the current active window is stored in:

            logical row 0 -> BRAM6
            logical row 1 -> BRAM7
            logical row 2 -> BRAM0
            logical row 3 -> BRAM1
            logical row 4 -> BRAM2

        Then row_sel contains:

            row_sel[0] = 8'b01000000
            row_sel[1] = 8'b10000000
            row_sel[2] = 8'b00000001
            row_sel[3] = 8'b00000010
            row_sel[4] = 8'b00000100

        If the BRAM outputs are:

            buffer_data[0] = 8'd30
            buffer_data[1] = 8'd40
            buffer_data[2] = 8'd50
            buffer_data[6] = 8'd10
            buffer_data[7] = 8'd20

        then this module produces:

            pixel_out[0] = buffer_data[6] = 8'd10
            pixel_out[1] = buffer_data[7] = 8'd20
            pixel_out[2] = buffer_data[0] = 8'd30
            pixel_out[3] = buffer_data[1] = 8'd40
            pixel_out[4] = buffer_data[2] = 8'd50

    No state, clock, reset, or buffer-management logic is stored in this module.
    It is purely combinational data-routing logic.
*/
//==============================================================================

module row_buffer_mux #(
    parameter int DATA_WIDTH  = 8,
    parameter int NUM_BUFFERS = 8,
    parameter int INIT_ROWS   = 5
)(
    input  logic [DATA_WIDTH-1:0]  buffer_data [0:NUM_BUFFERS-1], // Outputs from all physical BRAMs
    input  logic [NUM_BUFFERS-1:0] row_sel     [0:INIT_ROWS-1],   // Physical BRAM selected for each logical row
    input  logic [INIT_ROWS-1:0]   row_padding,

    output logic [DATA_WIDTH-1:0]  pixel_out   [0:INIT_ROWS-1]    // Selected BRAM output for each logical row
);

    integer row_idx;     // Iterates over the logical rows of the processing window
    integer buffer_idx;  // Iterates over all physical BRAMs


    //--------------------------------------------------------------------------
    // One-hot BRAM output selection
    //
    // Synthesizable for loops create the selection logic for each logical row.
    // The loops are unrolled during synthesis into parallel combinational hardware.
    //
    // For each logical row, the physical BRAM selectors are checked against
    // row_sel and the corresponding BRAM output is connected to pixel_out.
    // This results in independent one-hot controlled multiplexer for each logical row.
    //
    // Invalid row_sel values produce zero.
    //--------------------------------------------------------------------------

    always_comb begin

        for (row_idx = 0; row_idx < INIT_ROWS; row_idx = row_idx + 1) begin

            pixel_out[row_idx] = {DATA_WIDTH{1'b0}};

            if (~row_padding[row_idx]) begin

                for (buffer_idx = 0; buffer_idx < NUM_BUFFERS; buffer_idx = buffer_idx + 1) begin

                    if (row_sel[row_idx] ==
                        ({{(NUM_BUFFERS-1){1'b0}}, 1'b1} << buffer_idx))
                        pixel_out[row_idx] = buffer_data[buffer_idx];

                end

            end

        end

    end

endmodule