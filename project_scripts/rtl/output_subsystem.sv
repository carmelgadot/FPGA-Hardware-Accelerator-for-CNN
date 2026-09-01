//==============================================================================
/*
  Module Name : output_subsystem

  Description :
    Top-level output subsystem for the convolution-result path.

    This module combines the output-buffer control path and data path into one
    subsystem.

    Internal modules:
      1) output_buffer_controller
         - Controls the two-group ping-pong sequence.
         - Generates the common write and read addresses.
         - Generates the write and read enables for all physical output BRAMs.
         - Selects the active read group.
         - Generates out_valid aligned with the registered BRAM read data.

      2) output_buffer_bank
         - Contains the physical output BRAMs.
         - Stores the parallel convolution results.
         - Reads the completed output-buffer group.
         - Selects the active read group through output_buffer_mux.

    The output buffers are organized as two groups. For the default
    configuration:

        group 0 - BRAM0, BRAM1, BRAM2
        group 1 - BRAM3, BRAM4, BRAM5

    Each valid convolution cycle supplies PARALLEL_OUTPUTS results in parallel.
    The controller writes all lanes to the same address of the active write
    group. Once a complete group is available, it may be read while the other
    group is being filled.



    out_valid indicates when read_data contains a valid output-buffer read.
*/
//==============================================================================

module output_subsystem #(
    parameter int DATA_WIDTH         = 8,
    parameter int OUTPUT_LENGTH      = 640,
    parameter int ADDR_WIDTH         = 10,
    parameter int NUM_OUTPUT_BUFFERS = 6,
    parameter int PARALLEL_OUTPUTS   = 3,
    parameter int BRAM_READ_LATENCY  = 2
)(
    input  logic                            clk,        // System clock
    input  logic                            resetb,     // Asynchronous active-low reset

    input  logic                            conv_valid, // Parallel convolution results are valid
    input  logic [DATA_WIDTH-1:0]           data_in [0:PARALLEL_OUTPUTS-1],

    output logic [DATA_WIDTH-1:0]           read_data [0:PARALLEL_OUTPUTS-1],
    output logic                            out_valid   // read_data is valid this cycle
);


    //--------------------------------------------------------------------------
    // Internal control signals
    //--------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]          wr_addr;          // Common output-BRAM write address
    logic [ADDR_WIDTH-1:0]          rd_addr;          // Common output-BRAM read address

    logic [NUM_OUTPUT_BUFFERS-1:0]  bram_wr_en;       // Write enable per physical output BRAM
    logic [NUM_OUTPUT_BUFFERS-1:0]  bram_rd_en;       // Read enable per physical output BRAM

    logic                           read_group_sel;   // Group selected by output_buffer_mux


    //==========================================================================
    // Output Buffer Controller
    //
    // Generates all addresses, BRAM enables, group selection, and read-valid
    // timing required by the output-buffer bank.
    //==========================================================================

    output_buffer_controller #(
        .OUTPUT_LENGTH      (OUTPUT_LENGTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS),
        .BRAM_READ_LATENCY  (BRAM_READ_LATENCY)
    ) u_output_buffer_controller (
        .clk            (clk),
        .resetb         (resetb),

        .conv_valid     (conv_valid),

        .wr_addr        (wr_addr),
        .rd_addr        (rd_addr),

        .bram_wr_en     (bram_wr_en),
        .bram_rd_en     (bram_rd_en),

        .read_group_sel (read_group_sel),
        .out_valid      (out_valid)
    );


    //==========================================================================
    // Output Buffer Bank
    //
    // Stores the parallel convolution results in the selected write group and
    // returns the selected read group through read_data.
    //==========================================================================

    output_buffer_bank #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) u_output_buffer_bank (
        .clk            (clk),
        .resetb         (resetb),

        .rd_addr        (rd_addr),
        .wr_addr        (wr_addr),

        .data_in        (data_in),

        .wren           (bram_wr_en),
        .rden           (bram_rd_en),

        .read_group_sel (read_group_sel),

        .read_data      (read_data)
    );


endmodule
