//==============================================================================
// Module Name : input_buffers
// Description : Wrapper module for multiple single-port BRAM input buffers.
//
//               The module contains NUM_BUFFERS independent single-port BRAMs.
//               Each BRAM has its own write-enable and read-enable bit:
//
//                 - wren[i] controls writing to buffer i.
//                 - rden[i] controls reading from buffer i.
//
//               All buffers share the same write address, read address and
//               input data buses.
//
//               Write operation:
//                 When wren[i] is asserted, buffer i receives wr_addr as its
//                 address. On the next active clock edge, the value on data
//                 is written into buffer i at wr_addr.
//       
// 		Read operation:
// 		  When wren[i] is not asserted, buffer i receives rd_addr as its address.
// 		  The BRAM output is registered. If rden[i] is asserted,  
// 		  on the next active clock edge, the data is sampled from rd_addr to BRAM internal output register 
// 		  after one more clock edge the data sampled from output register to q[i] and becomes visible on q[i].
//
//               Simultaneous read and write:
//                 If both wren[i] and rden[i] are asserted for the same buffer,
//                 wr_addr is selected. Therefore, the read and write access
//                 the same address.
//
//                 The BRAM is configured with:
//
//                   read_during_write_mode_port_a =
//                       "NEW_DATA_NO_NBE_READ"
//
//                 Therefore, q[i] receives the newly written data.
//
//               Since all BRAMs are independent, one buffer may be written
//               while several other buffers are read in parallel.
//
//==============================================================================

module input_buffers #(
    parameter int DATA_WIDTH  = 8, //   Data width of each memory word (default: 8 bits)
    parameter int ADDR_WIDTH  = 10, //    Address width (default: 10 bits)
    parameter int NUM_BUFFERS = 16 //   Number of BRAM buffers (default: 16)
)(
    input  logic                          clk,      // Clock input shared by all BRAM instances
    input  logic                          resetb,   // Asynchronous active-low reset signal
    input  logic [ADDR_WIDTH-1:0]         rd_addr,  // Shared read address for active buffers
    input  logic [ADDR_WIDTH-1:0]         wr_addr,  // Shared write address for the fill buffer
    input  logic [DATA_WIDTH-1:0]         data,     // Shared input data bus written into selected buffer

    // One write-enable bit per buffer.
    // If wren[i] = 1, buffer i uses wr_addr and writes data on the next clock edge.
    input  logic [NUM_BUFFERS-1:0]        wren,

    // One read-enable bit per buffer.
    // If rden[i] = 1, buffer i performs a synchronous read.
    // The read result is provided through the registered output q[i].
    input  logic [NUM_BUFFERS-1:0]        rden,

    // Independent registered output from each physical BRAM buffer.
    output logic [DATA_WIDTH-1:0]         q [0:NUM_BUFFERS-1]
);

    genvar i;

    // Synthesizable generate loop that creates NUM_BUFFERS independent BRAM instances.
    generate
        for (i = 0; i < NUM_BUFFERS; i++) begin : gen_input_buffer

            logic [ADDR_WIDTH-1:0] bram_addr;

            // Select wr_addr when writing to buffer i; otherwise select rd_addr.
            assign bram_addr = (wren[i]) ? wr_addr : rd_addr;

            BRAM bram_inst (
                .aclr   (~resetb),   // BRAM expects active-high asynchronous clear
                .address(bram_addr),
                .clock  (clk),
                .data   (data),
                .rden   (rden[i]),   // Read enable dedicated to buffer i
                .wren   (wren[i]),   // Write enable dedicated to buffer i
                .q      (q[i])       // Registered read-data output of buffer i
            );

        end
    endgenerate

endmodule