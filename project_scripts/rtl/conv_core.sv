//==============================================================================
/*
  Module Name : conv_core

  Description :
    Performs three parallel 3x3 convolution operations using five active
    image rows. The nine kernel coefficients are supplied at run time and
    remain constant during image processing.

    After the raw signed convolution result is calculated, the module applies
    the same post-processing used in the software reference:

      1) Bias addition around the grayscale midpoint:
           y1 = y_conv + 128

      2) Contrast stretching around 128:
           y2 = (y1 - 128) * 2 + 128

      3) Saturation to the 8-bit grayscale range [0, 255].

    The final outputs are therefore unsigned 8-bit grayscale pixels.

  Note:
    The PE module must perform signed multiplication for the signed kernel
    coefficients to be interpreted correctly.
*/
//==============================================================================

module conv_core #(
    parameter int DATA_WIDTH = 8
)(
    input  logic                         clk,
    input  logic                         resetb,

    input  logic [DATA_WIDTH-1:0]        input_pixel0,
    input  logic [DATA_WIDTH-1:0]        input_pixel1,
    input  logic [DATA_WIDTH-1:0]        input_pixel2,
    input  logic [DATA_WIDTH-1:0]        input_pixel3,
    input  logic [DATA_WIDTH-1:0]        input_pixel4,

    input  logic signed [DATA_WIDTH-1:0] kernel [0:8],

    output logic [DATA_WIDTH-1:0]        data_out0,
    output logic [DATA_WIDTH-1:0]        data_out1,
    output logic [DATA_WIDTH-1:0]        data_out2
);

    //--------------------------------------------------------------------------
    // Width definitions
    //--------------------------------------------------------------------------
    localparam int SUM_WIDTH   = 2*DATA_WIDTH + 2;
    localparam int SUM3_WIDTH  = SUM_WIDTH + 2;
    localparam int POST_WIDTH  = SUM3_WIDTH + 1;

    localparam logic signed [POST_WIDTH-1:0] MIDPOINT = 128;
    localparam logic signed [POST_WIDTH-1:0] MAX_PIXEL = 255;

    //--------------------------------------------------------------------------
    // PE outputs and convolution sums
    //--------------------------------------------------------------------------
    logic signed [SUM_WIDTH-1:0]  pe_sum [0:8];

    logic signed [SUM3_WIDTH-1:0] sum_out0_comb;
    logic signed [SUM3_WIDTH-1:0] sum_out1_comb;
    logic signed [SUM3_WIDTH-1:0] sum_out2_comb;

    logic [DATA_WIDTH-1:0] data_out0_comb;
    logic [DATA_WIDTH-1:0] data_out1_comb;
    logic [DATA_WIDTH-1:0] data_out2_comb;


    //--------------------------------------------------------------------------
    // Post-processing function
    //
    // y1    = y_conv + 128
    // y2    = (y1 - 128) * 2 + 128
    // y_out = min(255, max(0, y2))
    //--------------------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] post_process(
        input logic signed [SUM3_WIDTH-1:0] conv_sum
    );
        logic signed [POST_WIDTH-1:0] conv_ext;
        logic signed [POST_WIDTH-1:0] biased;
        logic signed [POST_WIDTH-1:0] stretched;

        begin
            // Sign-extend the raw convolution result before post-processing.
            conv_ext = {{(POST_WIDTH-SUM3_WIDTH){conv_sum[SUM3_WIDTH-1]}},
                        conv_sum};

            // Add grayscale midpoint bias.
            biased = conv_ext + MIDPOINT;

            // Stretch contrast by a factor of two around the midpoint 128.
            stretched = ((biased - MIDPOINT) <<< 1) + MIDPOINT;

            // Saturate the result to the unsigned 8-bit grayscale range.
            if (stretched < 0)
                post_process = '0;
            else if (stretched > MAX_PIXEL)
                post_process = {DATA_WIDTH{1'b1}};
            else
                post_process = stretched[DATA_WIDTH-1:0];
        end
    endfunction


    //--------------------------------------------------------------------------
    // Processing Elements
    //
    // Three groups of three PEs generate three vertically adjacent 3x3
    // convolution outputs from the five active input rows.
    //--------------------------------------------------------------------------
    generate
        genvar i;
        for (i = 0; i < 9; i++) begin : pe_instances

            logic [DATA_WIDTH-1:0]        pe_pixel_in;
            logic signed [DATA_WIDTH-1:0] K0;
            logic signed [DATA_WIDTH-1:0] K1;
            logic signed [DATA_WIDTH-1:0] K2;

            always_comb begin

                // Select the image row used by this PE.
                case (i)
                    0: pe_pixel_in = input_pixel0;
                    1: pe_pixel_in = input_pixel1;
                    2: pe_pixel_in = input_pixel2;
                    3: pe_pixel_in = input_pixel1;
                    4: pe_pixel_in = input_pixel2;
                    5: pe_pixel_in = input_pixel3;
                    6: pe_pixel_in = input_pixel2;
                    7: pe_pixel_in = input_pixel3;
                    8: pe_pixel_in = input_pixel4;
                    default: pe_pixel_in = '0;
                endcase

                // Select the corresponding row of the 3x3 kernel.
                case (i % 3)
                    0: begin
                        K0 = kernel[0];
                        K1 = kernel[1];
                        K2 = kernel[2];
                    end

                    1: begin
                        K0 = kernel[3];
                        K1 = kernel[4];
                        K2 = kernel[5];
                    end

                    2: begin
                        K0 = kernel[6];
                        K1 = kernel[7];
                        K2 = kernel[8];
                    end

                    default: begin
                        K0 = '0;
                        K1 = '0;
                        K2 = '0;
                    end
                endcase
            end


            PE #(
                .DATA_WIDTH(DATA_WIDTH)
            ) pe_inst (
                .clk           (clk),
                .resetb        (resetb),
                .pixel         (pe_pixel_in),

                .K0            (K0),
                .K1            (K1),
                .K2            (K2),

                .pixel0        (),
                .pixel1        (),
                .pixel2        (),
                .row_shift_reg (),

                .mul0          (),
                .mul1          (),
                .mul2          (),
                .sum           (pe_sum[i])
            );
        end
    endgenerate


    //--------------------------------------------------------------------------
    // Combine PE results into three complete 3x3 convolution sums
    //--------------------------------------------------------------------------
    always_comb begin
        sum_out0_comb = pe_sum[0] + pe_sum[1] + pe_sum[2];
        sum_out1_comb = pe_sum[3] + pe_sum[4] + pe_sum[5];
        sum_out2_comb = pe_sum[6] + pe_sum[7] + pe_sum[8];

        data_out0_comb = post_process(sum_out0_comb);
        data_out1_comb = post_process(sum_out1_comb);
        data_out2_comb = post_process(sum_out2_comb);
    end


    //--------------------------------------------------------------------------
    // Register final post-processed 8-bit outputs
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            data_out0 <= '0;
            data_out1 <= '0;
            data_out2 <= '0;
        end
        else begin
            data_out0 <= data_out0_comb;
            data_out1 <= data_out1_comb;
            data_out2 <= data_out2_comb;
        end
    end

endmodule
