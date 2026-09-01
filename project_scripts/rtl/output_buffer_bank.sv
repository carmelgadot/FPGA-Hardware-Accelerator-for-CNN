//==============================================================================
/*
  Module Name : output_buffer_bank.sv

  Description :
    Top-level wrapper for the output-buffer memory subsystem.

    The module combines:

        - output_buffers
            Contains NUM_OUTPUT_BUFFERS independent physical BRAMs organized
            as two groups of PARALLEL_OUTPUTS buffers.

        - output_buffer_mux
            Selects one complete three-buffer group for the output read path.



    The control signals are supplied by output_buffer_controller. This wrapper
    contains no FSM, counters, or group-management state.
*/
//==============================================================================

module output_buffer_bank #(
    parameter int DATA_WIDTH         = 8,
    parameter int ADDR_WIDTH         = 10,
    parameter int NUM_OUTPUT_BUFFERS = 6,
    parameter int PARALLEL_OUTPUTS   = 3
)(
    input  logic                             clk,
    input  logic                             resetb,

    input  logic [ADDR_WIDTH-1:0]            rd_addr,
    input  logic [ADDR_WIDTH-1:0]            wr_addr,

    input  logic [DATA_WIDTH-1:0]            data_in [0:PARALLEL_OUTPUTS-1],

    input  logic [NUM_OUTPUT_BUFFERS-1:0]    wren,
    input  logic [NUM_OUTPUT_BUFFERS-1:0]    rden,

    input  logic                             read_group_sel,

    output logic [DATA_WIDTH-1:0]            read_data [0:PARALLEL_OUTPUTS-1]
);


    //--------------------------------------------------------------------------
    // Internal physical BRAM outputs
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] buffer_data [0:NUM_OUTPUT_BUFFERS-1];


    //--------------------------------------------------------------------------
    // Physical output buffers
    //--------------------------------------------------------------------------

    output_buffers #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) output_buffers_inst (
        .clk     (clk),
        .resetb  (resetb),
        .rd_addr (rd_addr),
        .wr_addr (wr_addr),
        .data_in (data_in),
        .wren    (wren),
        .rden    (rden),
        .q       (buffer_data)
    );


    //--------------------------------------------------------------------------
    // Read-group selection
    //--------------------------------------------------------------------------

    output_buffer_mux #(
        .DATA_WIDTH         (DATA_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS)
    ) output_buffer_mux_inst (
        .buffer_data    (buffer_data),
        .read_group_sel (read_group_sel),
        .read_data      (read_data)
    );


endmodule
