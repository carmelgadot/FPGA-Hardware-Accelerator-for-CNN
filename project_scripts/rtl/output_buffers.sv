//==============================================================================
// Module Name : output_buffers
// Description : Wrapper module for the physical output BRAMs.
//
//               The output subsystem contains NUM_OUTPUT_BUFFERS independent
//               single-port BRAMs organized as two groups of PARALLEL_OUTPUTS
//               buffers.
//
//               For the default configuration:
//
//                 group 0 -> BRAM0, BRAM1, BRAM2
//                 group 1 -> BRAM3, BRAM4, BRAM5
//
//               The three parallel convolution results are mapped by lane:
//
//                 data_in[0] -> BRAM0 or BRAM3
//                 data_in[1] -> BRAM1 or BRAM4
//                 data_in[2] -> BRAM2 or BRAM5
//
//               wren and rden contain one enable bit per physical BRAM.
//               The output-buffer controller is responsible for enabling all
//               three BRAMs of the active write or read group together.
//
//               All buffers share the same write address and read address.
//
//               Write operation:
//                 When wren[i] is asserted, BRAM i receives wr_addr and the
//                 data stream corresponding to its lane. The value is written
//                 on the active clock edge.
//
//               Read operation:
//                 When wren[i] is not asserted, BRAM i receives rd_addr.
//                 The BRAM output is registered. The read-data timing is the
//                 same as the BRAMs used by input_buffers.
//
//               Simultaneous read and write:
//                 The intended ping-pong operation writes one three-BRAM group
//                 while reading the other group. Since every BRAM is physically
//                 independent, these operations may proceed in parallel.
//
//==============================================================================

module output_buffers #(
    parameter int DATA_WIDTH         = 8,
    parameter int ADDR_WIDTH         = 10,
    parameter int NUM_OUTPUT_BUFFERS = 6,
    parameter int PARALLEL_OUTPUTS   = 3
)(
    input  logic                             clk,       // Clock shared by all BRAM instances
    input  logic                             resetb,    // Asynchronous active-low reset

    input  logic [ADDR_WIDTH-1:0]            rd_addr,   // Shared read address
    input  logic [ADDR_WIDTH-1:0]            wr_addr,   // Shared write address

    input  logic [DATA_WIDTH-1:0]            data_in [0:PARALLEL_OUTPUTS-1], // Three parallel convolution outputs

    input  logic [NUM_OUTPUT_BUFFERS-1:0]    wren,      // One write-enable bit per physical BRAM
    input  logic [NUM_OUTPUT_BUFFERS-1:0]    rden,      // One read-enable bit per physical BRAM

    output logic [DATA_WIDTH-1:0]            q [0:NUM_OUTPUT_BUFFERS-1]      // Registered BRAM outputs
);

    genvar i;


    //--------------------------------------------------------------------------
    // Physical output-buffer bank
    //--------------------------------------------------------------------------

    generate
        for (i = 0; i < NUM_OUTPUT_BUFFERS; i = i + 1) begin : gen_output_buffer

            localparam int LANE_IDX = i % PARALLEL_OUTPUTS;

            logic [ADDR_WIDTH-1:0] bram_addr;

            // A write has address priority for the selected physical BRAM.
            assign bram_addr = (wren[i]) ? wr_addr : rd_addr;

            BRAM bram_inst (
                .aclr    (~resetb),
                .address (bram_addr),
                .clock   (clk),
                .data    (data_in[LANE_IDX]),
                .rden    (rden[i]),
                .wren    (wren[i]),
                .q       (q[i])
            );

        end
    endgenerate

endmodule
