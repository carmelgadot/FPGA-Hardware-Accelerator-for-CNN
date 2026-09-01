//==============================================================================
/*
  Module Name : output_buffer_mux.sv

  Description :
    Selects one of two physical output-buffer groups and forwards the three
    corresponding BRAM outputs to the output read path.

    The output subsystem contains NUM_OUTPUT_BUFFERS physical BRAMs organized
    as two groups of PARALLEL_OUTPUTS buffers.

    For the default configuration:

        NUM_OUTPUT_BUFFERS = 6
        PARALLEL_OUTPUTS   = 3

        group 0 -> BRAM0, BRAM1, BRAM2
        group 1 -> BRAM3, BRAM4, BRAM5

    Each position inside a group corresponds to one of the three parallel
    convolution-result streams:

        lane 0 -> data_out0
        lane 1 -> data_out1
        lane 2 -> data_out2

    read_group_sel selects which complete group is connected to read_data.

        read_group_sel = 0:
            read_data[0] = buffer_data[0]
            read_data[1] = buffer_data[1]
            read_data[2] = buffer_data[2]

        read_group_sel = 1:
            read_data[0] = buffer_data[3]
            read_data[1] = buffer_data[4]
            read_data[2] = buffer_data[5]

    No state, clock, reset, or buffer-management logic is stored in this module.
    It is purely combinational data-routing logic.
*/
//==============================================================================

module output_buffer_mux #(
    parameter int DATA_WIDTH         = 8,
    parameter int NUM_OUTPUT_BUFFERS = 6,
    parameter int PARALLEL_OUTPUTS   = 3
)(
    input  logic [DATA_WIDTH-1:0] buffer_data   [0:NUM_OUTPUT_BUFFERS-1], // Outputs from all physical output BRAMs
    input  logic                  read_group_sel,                       // 0 selects group 0, 1 selects group 1

    output logic [DATA_WIDTH-1:0] read_data     [0:PARALLEL_OUTPUTS-1]   // Selected three-buffer group
);

    integer lane_idx;


    //--------------------------------------------------------------------------
    // Output-group selection
    //
    // The default architecture contains exactly two groups. Each group holds
    // PARALLEL_OUTPUTS independent BRAMs, one for each parallel convolution
    // output stream.
    //--------------------------------------------------------------------------

    always_comb begin

        for (lane_idx = 0;
             lane_idx < PARALLEL_OUTPUTS;
             lane_idx = lane_idx + 1) begin

            if (~read_group_sel)
                read_data[lane_idx] = buffer_data[lane_idx];
            else
                read_data[lane_idx] = buffer_data[PARALLEL_OUTPUTS + lane_idx];

        end

    end

endmodule
