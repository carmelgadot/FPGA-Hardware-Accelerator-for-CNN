//==============================================================================
/*
  Module Name : processing_unit

  Description :
    Top-level custom RTL processing unit for one convolution layer.

    The module integrates three main blocks:

      1) input_subsystem
         - Stores incoming padded image rows in circular row buffers.
         - Supplies INIT_ROWS pixels in parallel to the convolution datapath.
         - Exports rd_valid for each active-window BRAM read request.

      2) conv_core
         - Performs three parallel 3x3 convolutions for the current RTL
           configuration.
         - Produces PARALLEL_OUTPUTS convolution results in parallel.

      3) output_subsystem
         - Stores valid convolution results in two ping-pong output groups.
         - Reads completed output groups and produces out_valid.

    Horizontal padding:
      INPUT_ROW_LENGTH includes the horizontal zero-padding samples. For a
      3-pixel kernel and a 640-pixel output row using one zero on each side:

          INPUT_ROW_LENGTH = 642
          OUTPUT_LENGTH    = 640

      Padding zeros are legal input samples. They participate in convolution
      exactly like all other samples.

    Valid timing:
      rd_valid marks an input-BRAM read request. The data becomes visible after
      INPUT_BRAM_READ_LATENCY clocks. A KERNEL_WIDTH-deep valid history then
      marks when a complete horizontal window has been captured by conv_core.

      The resulting conv_launch_valid is delayed by CONV_CORE_LATENCY clocks
      to generate conv_valid aligned with data_out0..data_out2.


    The valid path is a shadow timing path only. It does not stall conv_core and
    does not implement backpressure.

  Current configuration note:
    The validity logic is parameterized by KERNEL_WIDTH, but the current
    conv_core implementation itself is fixed to a 3x3 kernel and five active
    input rows. A future 5x5 conv_core can reuse the same validity principle
    with updated architectural parameters and pipeline latency.
*/
//==============================================================================

module processing_unit #(
    parameter int DATA_WIDTH               = 8,

    parameter int INPUT_ROW_LENGTH         = 642,
    parameter int OUTPUT_LENGTH            = 640,
    parameter int ADDR_WIDTH               = 10,

    parameter int ROW_CNT_W                = 3,
    parameter int INIT_ROWS                = 5,
    parameter int STRIDE                   = 3,
    parameter int NUM_INPUT_BUFFERS        = 16,
    parameter int OCC_CNT_W                = 5,

    parameter int KERNEL_WIDTH             = 3,
    parameter int INPUT_BRAM_READ_LATENCY  = 2,
    parameter int CONV_CORE_LATENCY        = 3,

    parameter int NUM_OUTPUT_BUFFERS       = 6,
    parameter int PARALLEL_OUTPUTS         = 3,
    parameter int OUTPUT_BRAM_READ_LATENCY = 2
)(
    input  logic                            clk,
    input  logic                            resetb,

    input  logic                            data_valid,
    input  logic                            frame_done,
    input  logic [DATA_WIDTH-1:0]           data,

    input  logic signed [DATA_WIDTH-1:0]    kernel [0:8],

    output logic [DATA_WIDTH-1:0]           read_data [0:PARALLEL_OUTPUTS-1],
    output logic                            out_valid
);


    //--------------------------------------------------------------------------
    // Input-subsystem outputs
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] pixel_out [0:INIT_ROWS-1];
    logic                  input_rd_valid;


    //--------------------------------------------------------------------------
    // Convolution outputs
    //--------------------------------------------------------------------------

    logic [DATA_WIDTH-1:0] conv_data [0:PARALLEL_OUTPUTS-1];


    //--------------------------------------------------------------------------
    // Validity pipeline
    //--------------------------------------------------------------------------

    logic [INPUT_BRAM_READ_LATENCY-1:0] input_read_valid_pipe;
    logic                                input_sample_valid;

    logic [KERNEL_WIDTH-1:0]            sample_valid_history;
    logic                                conv_launch_valid;

    logic [CONV_CORE_LATENCY-1:0]       conv_valid_pipe;
    logic                                conv_valid;

    integer input_pipe_idx;
    integer history_idx;
    integer conv_pipe_idx;


    //==========================================================================
    // Input Subsystem
    //==========================================================================

    input_subsystem #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ROW_LENGTH  (INPUT_ROW_LENGTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ROW_CNT_W   (ROW_CNT_W),
        .INIT_ROWS   (INIT_ROWS),
        .STRIDE      (STRIDE),
        .NUM_BUFFERS (NUM_INPUT_BUFFERS),
        .OCC_CNT_W   (OCC_CNT_W)
    ) u_input_subsystem (
        .clk        (clk),
        .resetb     (resetb),
        .data_valid (data_valid),
        .frame_done (frame_done),
        .data       (data),

        .pixel_out  (pixel_out),
        .rd_valid   (input_rd_valid)
    );


    //==========================================================================
    // Input BRAM Read-Valid Alignment
    //
    // Delay the input read request by the documented registered BRAM latency.
    // The following history register samples input_sample_valid on a later
    // clock edge, matching the clock edge on which conv_core captures the
    // corresponding pixel_out values.
    //==========================================================================

    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb) begin
            input_read_valid_pipe <= '0;
        end
        else begin
            input_read_valid_pipe[0] <= input_rd_valid;

            for (input_pipe_idx = 1;
                 input_pipe_idx < INPUT_BRAM_READ_LATENCY;
                 input_pipe_idx = input_pipe_idx + 1) begin

                input_read_valid_pipe[input_pipe_idx]
                    <= input_read_valid_pipe[input_pipe_idx-1];
            end
        end
    end

    assign input_sample_valid =
        input_read_valid_pipe[INPUT_BRAM_READ_LATENCY-1];


    //==========================================================================
    // Horizontal Window Valid Generation
    //
    // A complete convolution window exists only after KERNEL_WIDTH consecutive
    // valid samples have been captured. Any gap between row scans shifts zeros
    // into the history and automatically restarts the horizontal warm-up.
    //==========================================================================

    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb) begin
            sample_valid_history <= '0;
        end
        else begin
            sample_valid_history[0] <= input_sample_valid;

            for (history_idx = 1;
                 history_idx < KERNEL_WIDTH;
                 history_idx = history_idx + 1) begin

                sample_valid_history[history_idx]
                    <= sample_valid_history[history_idx-1];
            end
        end
    end

    assign conv_launch_valid = &sample_valid_history;


    //==========================================================================
    // Convolution Core
    //==========================================================================

    conv_core #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_conv_core (
        .clk          (clk),
        .resetb       (resetb),

        .input_pixel0 (pixel_out[0]),
        .input_pixel1 (pixel_out[1]),
        .input_pixel2 (pixel_out[2]),
        .input_pixel3 (pixel_out[3]),
        .input_pixel4 (pixel_out[4]),

        .kernel       (kernel),

        .data_out0    (conv_data[0]),
        .data_out1    (conv_data[1]),
        .data_out2    (conv_data[2])
    );


    //==========================================================================
    // conv_valid Alignment
    //
    // Delay the completed-window marker by the externally verified conv_core
    // pipeline latency so conv_valid is asserted in the same cycle as the
    // corresponding conv_data values.
    //==========================================================================

    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb) begin
            conv_valid_pipe <= '0;
        end
        else begin
            conv_valid_pipe[0] <= conv_launch_valid;

            for (conv_pipe_idx = 1;
                 conv_pipe_idx < CONV_CORE_LATENCY;
                 conv_pipe_idx = conv_pipe_idx + 1) begin

                conv_valid_pipe[conv_pipe_idx]
                    <= conv_valid_pipe[conv_pipe_idx-1];
            end
        end
    end

    assign conv_valid = conv_valid_pipe[CONV_CORE_LATENCY-1];


    //==========================================================================
    // Output Subsystem
    //==========================================================================

    output_subsystem #(
        .DATA_WIDTH         (DATA_WIDTH),
        .OUTPUT_LENGTH      (OUTPUT_LENGTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .NUM_OUTPUT_BUFFERS (NUM_OUTPUT_BUFFERS),
        .PARALLEL_OUTPUTS   (PARALLEL_OUTPUTS),
        .BRAM_READ_LATENCY  (OUTPUT_BRAM_READ_LATENCY)
    ) u_output_subsystem (
        .clk        (clk),
        .resetb     (resetb),

        .conv_valid (conv_valid),
        .data_in    (conv_data),

        .read_data  (read_data),
        .out_valid  (out_valid)
    );


endmodule
