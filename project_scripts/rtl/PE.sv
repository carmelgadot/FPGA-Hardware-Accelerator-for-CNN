// ============================================================================
// Module: PE (Processing Element)
// Description: This module performs a 1D convolution using a 3-tap kernel.
//              It maintains a shift register for the last 3 pixels,
//              multiplies each with a kernel coefficient (K0, K1, K2),
//              and computes the signed sum of the products.
// ============================================================================

module PE #( 
    parameter int DATA_WIDTH = 8,
    parameter int KERNEL_WIDTH = 3
)(
    input  logic clk,                       // Clock
    input  logic resetb,                   // Active-low reset
    input  logic [DATA_WIDTH-1:0] pixel,   // Input pixel stream

    input  logic signed [DATA_WIDTH-1:0] K0, // Kernel coefficient 0 (runtime)
    input  logic signed [DATA_WIDTH-1:0] K1, // Kernel coefficient 1 (runtime)
    input  logic signed [DATA_WIDTH-1:0] K2, // Kernel coefficient 2 (runtime)

    output logic [DATA_WIDTH-1:0] pixel0,  // Oldest pixel in window
    output logic [DATA_WIDTH-1:0] pixel1,  // Middle pixel in window
    output logic [DATA_WIDTH-1:0] pixel2,  // Most recent pixel in window
    output logic [3*DATA_WIDTH-1:0] row_shift_reg, // 3-pixel shift register

    output logic signed [(2*DATA_WIDTH)-1:0] mul0, // pixel0 × K0
    output logic signed [(2*DATA_WIDTH)-1:0] mul1, // pixel1 × K1
    output logic signed [(2*DATA_WIDTH)-1:0] mul2, // pixel2 × K2
    // Enough to hold the signed sum of 3 multiplication results
    output logic signed [2*DATA_WIDTH+1:0] sum      // Convolution sum
);

    // Signed, zero-extended pixel values for multiplication with signed kernels
    logic signed [DATA_WIDTH:0] pixel0_signed;
    logic signed [DATA_WIDTH:0] pixel1_signed;
    logic signed [DATA_WIDTH:0] pixel2_signed;

    // Shift register: stores the last 3 pixels
    always_ff @(posedge clk or negedge resetb) begin
        if (!resetb)
            row_shift_reg <= {3*DATA_WIDTH{1'b0}};
        else
            row_shift_reg <= {pixel, row_shift_reg[3*DATA_WIDTH-1:DATA_WIDTH]};
    end

    // Extract individual pixels from the shift register
    assign pixel2 = row_shift_reg[3*DATA_WIDTH-1:2*DATA_WIDTH];
    assign pixel1 = row_shift_reg[2*DATA_WIDTH-1:DATA_WIDTH];
    assign pixel0 = row_shift_reg[DATA_WIDTH-1:0];

    // Preserve the full unsigned pixel range (0 to 255) while allowing
    // signed multiplication with negative kernel coefficients
    assign pixel0_signed = {1'b0, pixel0};
    assign pixel1_signed = {1'b0, pixel1};
    assign pixel2_signed = {1'b0, pixel2};

    // Perform multiply and accumulate (MAC)
    always_ff @(posedge clk or negedge resetb) begin
        if (!resetb) begin
            mul0 <= {(2*DATA_WIDTH){1'b0}};
            mul1 <= {(2*DATA_WIDTH){1'b0}};
            mul2 <= {(2*DATA_WIDTH){1'b0}};
            sum  <= {(2*DATA_WIDTH+2){1'b0}};
        end else begin
            mul0 <= pixel0_signed * K0;
            mul1 <= pixel1_signed * K1;
            mul2 <= pixel2_signed * K2;
            sum  <= mul0 + mul1 + mul2;
        end
    end

endmodule
