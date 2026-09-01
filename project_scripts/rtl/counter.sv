//==============================================================================
// Module Name : counter
// Description : Parameterized up-counter with enable, clear, and asynchronous reset.
//
// Parameters  :
//   - WIDTH : Width of the counter (default: 7 bits)
//
// Ports       :
//   - clk     : Clock input
//   - resetb  : Asynchronous active-low reset
//   - en      : Enable signal for incrementing the counter
//   - clr     : Synchronous clear signal
//   - count   : Current counter value
//==============================================================================

module counter #(parameter int WIDTH = 7) (
    input  logic                   clk,                   // Clock signal
    input  logic                   resetb,                // Asynchronous active-low reset
    input  logic                   en,                    // Enable signal for counting
    input  logic                   clr,                   // Synchronous clear signal
    output logic [WIDTH-1:0]       count                  // Counter output
);

    // Counter logic: triggered on rising edge of clock or falling edge of resetb
    always_ff @(posedge clk or negedge resetb) begin 
        if (~resetb)
            // Asynchronous reset: clear count to 0
            count <= {WIDTH{1'b0}};
        else begin
            if (clr)
                // Synchronous clear: reset count to 0
                count <= {WIDTH{1'b0}};
            else begin
                if (en)
                    // If enabled, increment the count by 1
                    count <= count + {{(WIDTH-1){1'b0}}, 1'b1};
                else
                    // If not enabled, retain current value
                    count <= count;
            end
        end            
    end

endmodule
