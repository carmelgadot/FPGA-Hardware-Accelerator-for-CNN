//==============================================================================
/*
  Module Name : row_buffer_bank.sv

  Description :
    Top-level wrapper for the row-buffer memory subsystem.

    The module combines:

        - input_buffers
            Contains NUM_BUFFERS independent physical BRAM row buffers.

        - row_buffer_mux
            Maps the physical BRAM outputs to the logical rows of the
            current processing window.

    Data flow:
	input_buffers -> buffer_data -> row_buffer_mux -> pixel_out

    All BRAM control signals are passed directly to input_buffers.

    The outputs of the physical BRAMs are connected internally
    to row_buffer_mux through buffer_data.

    row_sel determines which physical BRAM is associated with each logical
    row of the active processing window.



    No additional state, control logic, or buffering is implemented in this
    wrapper. Its purpose is only to connect the physical row buffers to the
    logical row-selection logic.
*/
//==============================================================================

module row_buffer_bank #(
    parameter int DATA_WIDTH  = 8,   // Data width of each pixel / BRAM word
    parameter int ADDR_WIDTH  = 10,  // Address width of each row buffer
    parameter int NUM_BUFFERS = 16,  // Number of physical BRAM row buffers
    parameter int INIT_ROWS   = 5    // Number of logical rows in active window
)(
    input  logic                          clk,      // Clock shared by all physical BRAMs
    input  logic                          resetb,   // Asynchronous active-low reset for BRAM outputs

    input  logic [ADDR_WIDTH-1:0]         rd_addr,  // Shared BRAM read address
    input  logic [ADDR_WIDTH-1:0]         wr_addr,  // Shared BRAM write address
    input  logic [DATA_WIDTH-1:0]         data,     // Input data written into selected BRAM

    input  logic [NUM_BUFFERS-1:0]        wren,     // One write-enable bit per physical BRAM
    input  logic [NUM_BUFFERS-1:0]        rden,     // One read-enable bit per physical BRAM

    // One-hot physical-BRAM selection for each logical row in the active window.
    input  logic [NUM_BUFFERS-1:0]        row_sel   [0:INIT_ROWS-1],

    input  logic [INIT_ROWS-1:0]          row_padding,

    // BRAM data reordered according to the logical rows of the active window.
    output logic [DATA_WIDTH-1:0]         pixel_out [0:INIT_ROWS-1]
);


    //--------------------------------------------------------------------------
    // Internal physical BRAM outputs
    //
    // buffer_data[i] carries the registered output of physical BRAM i.
    // These signals connect input_buffers directly to row_buffer_mux.
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] buffer_data [0:NUM_BUFFERS-1];


    //--------------------------------------------------------------------------
    // Physical row-buffer bank
    //
    // Contains NUM_BUFFERS independent single-port BRAM instances.
    // Read/write addresses, data, and enables are passed directly from the
    // wrapper inputs.
    //--------------------------------------------------------------------------

    input_buffers #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .NUM_BUFFERS (NUM_BUFFERS)
    ) input_buffers_inst (
        .clk     (clk),
        .resetb  (resetb),
        .rd_addr (rd_addr),
        .wr_addr (wr_addr),
        .data    (data),
        .wren    (wren),
        .rden    (rden),
        .q       (buffer_data)
    );


    //--------------------------------------------------------------------------
    // Logical-row read selection
    //
    // Maps each logical row of the active processing window to the output of
    // its currently assigned physical BRAM according to row_sel.
    //--------------------------------------------------------------------------

    row_buffer_mux #(
        .DATA_WIDTH  (DATA_WIDTH),
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS)
    ) row_buffer_mux_inst (
        .buffer_data (buffer_data),
        .row_sel     (row_sel),
        .row_padding (row_padding),
        .pixel_out   (pixel_out)
    );


endmodule
