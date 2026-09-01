//==============================================================================
/*
  Module Name : input_subsystem

  Description :
    Top-level input subsystem for the row-buffer and convolution input path.

    This module combines the row-buffer control path and data path into one
    subsystem.

    Internal modules:
      1) row_buffer_controller
         - Controls the row-buffer operation.
         - Generates the read and write addresses.
         - Generates the read and write enables for each physical BRAM.
         - Generates the logical-row selectors used to map the active window
           to the physical row buffers.

      2) row_buffer_bank
         - Contains the physical input row buffers.
         - Stores incoming pixel data.
         - Reads the active row buffers.
         - Maps the physical BRAM outputs to the logical processing rows
           according to row_sel.

    The control signals connecting row_buffer_controller and row_buffer_bank
    are internal to this subsystem:

      - wr_addr
      - rd_addr
      - bram_wr_en
      - bram_rd_en
      - row_sel
      - row_padding

    External data flow:

        data + data_valid
               |
               v
        input_subsystem
               |
               v
      pixel_out[0:INIT_ROWS-1]

    The pixel_out array contains one pixel from each logical row of the active
    processing window and can be connected directly to the processing stage.
*/
//==============================================================================

module input_subsystem #(
    parameter int DATA_WIDTH  = 8,
    parameter int ROW_LENGTH  = 642,
    parameter int ADDR_WIDTH  = 10,
    parameter int ROW_CNT_W   = 3,
    parameter int INIT_ROWS   = 5,
    parameter int STRIDE      = 3,
    parameter int NUM_BUFFERS = 16,
    parameter int OCC_CNT_W   = 5
)(
    input  logic                         clk,                     // System clock
    input  logic                         resetb,                  // Asynchronous active-low reset
    input  logic                         data_valid,              // Incoming pixel is valid
    input  logic                         frame_done,              // End of real rows for current frame
    input  logic [DATA_WIDTH-1:0]        data,                    // Incoming pixel data

    output logic [DATA_WIDTH-1:0]        pixel_out [0:INIT_ROWS-1], // Pixel from each logical row
    output logic                         rd_valid                  // Valid active-window read request
);


    logic [ADDR_WIDTH-1:0]       wr_addr;                 // Current BRAM write address
    logic [ADDR_WIDTH-1:0]       rd_addr;                 // Current BRAM read address

    logic [NUM_BUFFERS-1:0]      bram_wr_en;              // Write enable for each physical BRAM
    logic [NUM_BUFFERS-1:0]      bram_rd_en;              // Read enable for each physical BRAM

    logic [NUM_BUFFERS-1:0]      row_sel [0:INIT_ROWS-1]; // Physical BRAM selected for each logical row
    logic [INIT_ROWS-1:0]        row_padding;             // Padding indication for each logical row

    assign rd_valid = |bram_rd_en;


    //==========================================================================
    // Row Buffer Controller
    //
    // Controls the complete row-buffer sequence and generates the addresses,
    // BRAM enables, and logical-row selectors required by row_buffer_bank.
    //==========================================================================

    row_buffer_controller #(
        .ROW_LENGTH  (ROW_LENGTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ROW_CNT_W   (ROW_CNT_W),
        .INIT_ROWS   (INIT_ROWS),
        .STRIDE      (STRIDE),
        .NUM_BUFFERS (NUM_BUFFERS),
        .OCC_CNT_W   (OCC_CNT_W)
    ) u_row_buffer_controller (
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
    // Row Buffer Bank
    //
    // Stores the incoming pixel data in the physical row buffers and uses the
    // controller outputs to read and map the active rows to pixel_out.
    //==========================================================================

    row_buffer_bank #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .NUM_BUFFERS (NUM_BUFFERS),
        .INIT_ROWS   (INIT_ROWS)
    ) u_row_buffer_bank (
        .clk         (clk),
        .resetb      (resetb),

        .rd_addr     (rd_addr),
        .wr_addr     (wr_addr),

        .data        (data),

        .wren        (bram_wr_en),
        .rden        (bram_rd_en),

        .row_sel     (row_sel),
        .row_padding (row_padding),

        .pixel_out   (pixel_out)
    );


endmodule