`timescale 1ns/1ps

//==============================================================================
/*
  Testbench Name : PE_tb

  Description :
    Functional verification of the PE (Processing Element) module.

    The DUT stores the last three input pixels, multiplies them by three
    runtime signed kernel coefficients, and produces the signed sum of the
    three products.

  General Goals :
    - Verify asynchronous active-low reset behavior.
    - Verify correct 3-pixel shift-register operation.
    - Verify pixel0 / pixel1 / pixel2 ordering.
    - Verify multiplication with positive and negative kernel coefficients.
    - Verify unsigned pixel values above 127 are handled correctly.
    - Verify signed accumulation of the three products.
    - Verify runtime changes of the kernel coefficients.
    - Verify minimum and maximum signed kernel values.
    - Verify the PE pipeline latency cycle by cycle.

  Reference-Model Methodology :
    - The golden model is intentionally independent of the DUT implementation.
    - It stores only an abstract history of the last three input samples.
    - The expected convolution value is calculated directly from the
      mathematical 3-tap dot product:

          oldest*K0 + middle*K1 + newest*K2

    - The golden model does NOT reproduce the DUT multiplier-register and
      accumulator-register implementation.
    - A single expected-result delay register models only the externally
      observable PE latency from the multiplier sampling edge to the sum.
    - The multiplier outputs are checked directly from the abstract pixel
      history and kernel values, without deriving them from DUT internals.

  Synchronization Methodology :
    - sync() is a dedicated task used only for clock synchronization.
    - Normal stimulus is changed only after sync() returns.
    - resetb deassertion is performed only after sync().
    - resetb assertion is intentionally applied between clock edges to verify
      asynchronous reset behavior.
    - Assertions are used for automatic pass/fail detection.
*/
//==============================================================================

module PE_tb;

    //==========================================================================
    // Parameters
    //==========================================================================

    localparam int DATA_WIDTH   = 8;
    localparam int KERNEL_WIDTH = 3;

    localparam time CLK_PERIOD = 10ns;


    //==========================================================================
    // DUT Signals
    //==========================================================================

    logic clk;
    logic resetb;

    logic [DATA_WIDTH-1:0] pixel;

    logic signed [DATA_WIDTH-1:0] K0;
    logic signed [DATA_WIDTH-1:0] K1;
    logic signed [DATA_WIDTH-1:0] K2;

    logic [DATA_WIDTH-1:0] pixel0;
    logic [DATA_WIDTH-1:0] pixel1;
    logic [DATA_WIDTH-1:0] pixel2;

    logic [3*DATA_WIDTH-1:0] row_shift_reg;

    logic signed [(2*DATA_WIDTH)-1:0] mul0;
    logic signed [(2*DATA_WIDTH)-1:0] mul1;
    logic signed [(2*DATA_WIDTH)-1:0] mul2;

    logic signed [2*DATA_WIDTH+1:0] sum;


    //==========================================================================
    // Independent Golden Model
    //==========================================================================

    // Abstract pixel history only.
    // history0 = oldest pixel, history2 = most recent pixel.
    logic [DATA_WIDTH-1:0] history0;
    logic [DATA_WIDTH-1:0] history1;
    logic [DATA_WIDTH-1:0] history2;

    // Expected sum produced one clock after the products for a window are
    // sampled by the PE.
    logic signed [2*DATA_WIDTH+1:0] expected_sum_delayed;

    int unsigned captured_pixel_count;
    bit          expected_sum_valid;


    //==========================================================================
    // Test Status
    //==========================================================================

    int unsigned error_count;
    int unsigned check_count;


    //==========================================================================
    // Coverage Tracking
    //==========================================================================

    bit reset_covered;
    bit positive_kernel_covered;
    bit negative_kernel_covered;
    bit high_unsigned_pixel_covered;
    bit runtime_kernel_change_covered;
    bit minimum_kernel_value_covered;
    bit maximum_kernel_value_covered;
    bit full_window_covered;
    bit pipeline_latency_covered;


    //==========================================================================
    // DUT Instance
    //==========================================================================

    PE #(
        .DATA_WIDTH   (DATA_WIDTH),
        .KERNEL_WIDTH (KERNEL_WIDTH)
    ) dut (
        .clk           (clk),
        .resetb        (resetb),
        .pixel         (pixel),

        .K0            (K0),
        .K1            (K1),
        .K2            (K2),

        .pixel0        (pixel0),
        .pixel1        (pixel1),
        .pixel2        (pixel2),
        .row_shift_reg (row_shift_reg),

        .mul0          (mul0),
        .mul1          (mul1),
        .mul2          (mul2),
        .sum           (sum)
    );


    //==========================================================================
    // Clock Generation
    //==========================================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end


    //==========================================================================
    // Golden-Model Functions
    //==========================================================================

    //--------------------------------------------------------------------------
    // Calculate one product mathematically using integer arithmetic.
    //
    // This function intentionally does not reproduce the DUT's internal
    // zero-extension signal or multiplier implementation.
    //--------------------------------------------------------------------------

    function automatic integer signed golden_product(
        input logic [DATA_WIDTH-1:0]        pixel_value,
        input logic signed [DATA_WIDTH-1:0] kernel_value
    );
        integer signed pixel_int;
        integer signed kernel_int;

        begin
            pixel_int  = pixel_value;
            kernel_int = kernel_value;

            golden_product = pixel_int * kernel_int;
        end
    endfunction


    //--------------------------------------------------------------------------
    // Calculate the complete 3-tap dot product directly from the mathematical
    // definition, without using expected multiplier pipeline registers.
    //--------------------------------------------------------------------------

    function automatic integer signed golden_dot_product(
        input logic [DATA_WIDTH-1:0]        oldest_pixel,
        input logic [DATA_WIDTH-1:0]        middle_pixel,
        input logic [DATA_WIDTH-1:0]        newest_pixel,
        input logic signed [DATA_WIDTH-1:0] kernel0,
        input logic signed [DATA_WIDTH-1:0] kernel1,
        input logic signed [DATA_WIDTH-1:0] kernel2
    );
        begin
            golden_dot_product =
                  golden_product(oldest_pixel, kernel0)
                + golden_product(middle_pixel, kernel1)
                + golden_product(newest_pixel, kernel2);
        end
    endfunction


    //==========================================================================
    // Utility Tasks
    //==========================================================================

    //--------------------------------------------------------------------------
    // Synchronization task
    //
    // Normal stimulus is changed immediately after sync() returns.
    // resetb assertion is intentionally excluded when asynchronous behavior
    // is being tested.
    //--------------------------------------------------------------------------

    task automatic sync;
        begin
            @(posedge clk);
            #1ps;
        end
    endtask


    //--------------------------------------------------------------------------
    // Print test banner.
    //--------------------------------------------------------------------------

    task automatic print_banner(
        input string test_name
    );
        begin
            $display("");
            $display("================================================================");
            $display("START TEST: %s", test_name);
            $display("TIME      : %0t", $time);
            $display("================================================================");
        end
    endtask


    //--------------------------------------------------------------------------
    // Clear only the abstract golden-model state.
    //--------------------------------------------------------------------------

    task automatic clear_golden_model;
        begin
            history0             = {DATA_WIDTH{1'b0}};
            history1             = {DATA_WIDTH{1'b0}};
            history2             = {DATA_WIDTH{1'b0}};
            expected_sum_delayed = {(2*DATA_WIDTH+2){1'b0}};
            captured_pixel_count = 0;
            expected_sum_valid   = 1'b0;
        end
    endtask


    //--------------------------------------------------------------------------
    // Check all reset values immediately after asynchronous reset assertion.
    //--------------------------------------------------------------------------

    task automatic check_reset_outputs;
        begin
            check_count = check_count + 1;
            assert (row_shift_reg === {3*DATA_WIDTH{1'b0}})
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: row_shift_reg expected=0 got=%h", row_shift_reg);
            end

            check_count = check_count + 1;
            assert (pixel0 === {DATA_WIDTH{1'b0}})
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: pixel0 expected=0 got=%0d", pixel0);
            end

            check_count = check_count + 1;
            assert (pixel1 === {DATA_WIDTH{1'b0}})
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: pixel1 expected=0 got=%0d", pixel1);
            end

            check_count = check_count + 1;
            assert (pixel2 === {DATA_WIDTH{1'b0}})
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: pixel2 expected=0 got=%0d", pixel2);
            end

            check_count = check_count + 1;
            assert (mul0 === 0)
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: mul0 expected=0 got=%0d", mul0);
            end

            check_count = check_count + 1;
            assert (mul1 === 0)
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: mul1 expected=0 got=%0d", mul1);
            end

            check_count = check_count + 1;
            assert (mul2 === 0)
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: mul2 expected=0 got=%0d", mul2);
            end

            check_count = check_count + 1;
            assert (sum === 0)
            else begin
                error_count = error_count + 1;
                $error("RESET mismatch: sum expected=0 got=%0d", sum);
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Check one completed clock cycle using the independent golden model.
    //
    // At the clock edge just completed:
    //   - mul0/mul1/mul2 sampled the PREVIOUS 3-pixel window.
    //   - sum captured the dot product sampled one clock earlier.
    //   - row_shift_reg captured the current input pixel.
    //
    // Only this externally observable timing relationship is modeled. The
    // DUT's internal multiplier-register/accumulator implementation is not.
    //--------------------------------------------------------------------------

    task automatic check_cycle;
        integer signed direct_mul0;
        integer signed direct_mul1;
        integer signed direct_mul2;
        integer signed direct_dot_product;

        logic [DATA_WIDTH-1:0] next_history0;
        logic [DATA_WIDTH-1:0] next_history1;
        logic [DATA_WIDTH-1:0] next_history2;
        logic [3*DATA_WIDTH-1:0] expected_shift_register;

        begin
            if (!resetb) begin
                clear_golden_model();
                check_reset_outputs();
            end
            else begin

                // Direct mathematical result for the window that existed
                // immediately before this edge.
                direct_mul0 = golden_product(history0, K0);
                direct_mul1 = golden_product(history1, K1);
                direct_mul2 = golden_product(history2, K2);

                direct_dot_product = golden_dot_product(
                    history0,
                    history1,
                    history2,
                    K0,
                    K1,
                    K2
                );


                // -------------------------------------------------------------
                // Check registered multipliers directly from the abstract
                // window and current kernel values.
                // -------------------------------------------------------------

                check_count = check_count + 1;
                assert (mul0 === direct_mul0)
                else begin
                    error_count = error_count + 1;
                    $error(
                        "mul0 mismatch: pixel=%0d K0=%0d expected=%0d got=%0d",
                        history0, K0, direct_mul0, mul0
                    );
                end

                check_count = check_count + 1;
                assert (mul1 === direct_mul1)
                else begin
                    error_count = error_count + 1;
                    $error(
                        "mul1 mismatch: pixel=%0d K1=%0d expected=%0d got=%0d",
                        history1, K1, direct_mul1, mul1
                    );
                end

                check_count = check_count + 1;
                assert (mul2 === direct_mul2)
                else begin
                    error_count = error_count + 1;
                    $error(
                        "mul2 mismatch: pixel=%0d K2=%0d expected=%0d got=%0d",
                        history2, K2, direct_mul2, mul2
                    );
                end


                // -------------------------------------------------------------
                // Check the accumulated result from the PREVIOUS sampled
                // window. This is the only delay state kept by the golden model.
                // -------------------------------------------------------------

                check_count = check_count + 1;
                assert (sum === expected_sum_delayed)
                else begin
                    error_count = error_count + 1;
                    $error(
                        "sum mismatch: expected=%0d got=%0d",
                        expected_sum_delayed,
                        sum
                    );
                end

                if (expected_sum_valid)
                    pipeline_latency_covered = 1'b1;


                // -------------------------------------------------------------
                // Independently predict the visible shift-register state after
                // the edge that just occurred.
                // -------------------------------------------------------------

                next_history0 = history1;
                next_history1 = history2;
                next_history2 = pixel;

                expected_shift_register = {
                    next_history2,
                    next_history1,
                    next_history0
                };

                check_count = check_count + 1;
                assert (row_shift_reg === expected_shift_register)
                else begin
                    error_count = error_count + 1;
                    $error(
                        "row_shift_reg mismatch: expected=%h got=%h",
                        expected_shift_register,
                        row_shift_reg
                    );
                end

                check_count = check_count + 1;
                assert (pixel0 === next_history0)
                else begin
                    error_count = error_count + 1;
                    $error("pixel0 mismatch: expected=%0d got=%0d", next_history0, pixel0);
                end

                check_count = check_count + 1;
                assert (pixel1 === next_history1)
                else begin
                    error_count = error_count + 1;
                    $error("pixel1 mismatch: expected=%0d got=%0d", next_history1, pixel1);
                end

                check_count = check_count + 1;
                assert (pixel2 === next_history2)
                else begin
                    error_count = error_count + 1;
                    $error("pixel2 mismatch: expected=%0d got=%0d", next_history2, pixel2);
                end


                // -------------------------------------------------------------
                // Advance only the abstract model state.
                // -------------------------------------------------------------

                expected_sum_delayed = direct_dot_product;
                expected_sum_valid   = (captured_pixel_count >= 3);

                history0 = next_history0;
                history1 = next_history1;
                history2 = next_history2;

                if (captured_pixel_count < 3)
                    captured_pixel_count = captured_pixel_count + 1;

                if (captured_pixel_count >= 3)
                    full_window_covered = 1'b1;
            end
        end
    endtask


    //--------------------------------------------------------------------------
    // Apply one new input pixel after a synchronized edge.
    //--------------------------------------------------------------------------

    task automatic apply_pixel(
        input logic [DATA_WIDTH-1:0] pixel_value
    );
        begin
            pixel = pixel_value;

            if (pixel_value > 8'd127)
                high_unsigned_pixel_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Change all three runtime kernel coefficients after a synchronized edge.
    //--------------------------------------------------------------------------

    task automatic apply_kernel(
        input logic signed [DATA_WIDTH-1:0] kernel0,
        input logic signed [DATA_WIDTH-1:0] kernel1,
        input logic signed [DATA_WIDTH-1:0] kernel2
    );
        begin
            K0 = kernel0;
            K1 = kernel1;
            K2 = kernel2;

            if ((kernel0 < 0) || (kernel1 < 0) || (kernel2 < 0))
                negative_kernel_covered = 1'b1;

            if ((kernel0 > 0) || (kernel1 > 0) || (kernel2 > 0))
                positive_kernel_covered = 1'b1;

            if ((kernel0 == -128) || (kernel1 == -128) || (kernel2 == -128))
                minimum_kernel_value_covered = 1'b1;

            if ((kernel0 == 127) || (kernel1 == 127) || (kernel2 == 127))
                maximum_kernel_value_covered = 1'b1;
        end
    endtask


    //--------------------------------------------------------------------------
    // Verify that all intended coverage points were exercised.
    //--------------------------------------------------------------------------

    task automatic check_coverage;
        begin
            if (!reset_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: asynchronous reset was not covered");
            end

            if (!positive_kernel_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: positive kernel coefficients were not covered");
            end

            if (!negative_kernel_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: negative kernel coefficients were not covered");
            end

            if (!high_unsigned_pixel_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: unsigned pixels above 127 were not covered");
            end

            if (!runtime_kernel_change_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: runtime kernel change was not covered");
            end

            if (!minimum_kernel_value_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: minimum signed kernel coefficient was not covered");
            end

            if (!maximum_kernel_value_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: maximum signed kernel coefficient was not covered");
            end

            if (!full_window_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: a complete 3-pixel window was not covered");
            end

            if (!pipeline_latency_covered) begin
                error_count = error_count + 1;
                $error("COVERAGE FAILED: PE pipeline latency was not covered");
            end
        end
    endtask


    //==========================================================================
    // Test Sequence
    //==========================================================================

    initial begin

        //--------------------------------------------------------------------------
        // Initial values
        //--------------------------------------------------------------------------

        resetb = 1'b0;
        pixel  = {DATA_WIDTH{1'b0}};

        K0 = '0;
        K1 = '0;
        K2 = '0;

        error_count = 0;
        check_count = 0;

        reset_covered                  = 1'b0;
        positive_kernel_covered        = 1'b0;
        negative_kernel_covered        = 1'b0;
        high_unsigned_pixel_covered    = 1'b0;
        runtime_kernel_change_covered  = 1'b0;
        minimum_kernel_value_covered   = 1'b0;
        maximum_kernel_value_covered   = 1'b0;
        full_window_covered            = 1'b0;
        pipeline_latency_covered       = 1'b0;

        clear_golden_model();


        //======================================================================
        // TEST 1: Initial reset and reset release
        //======================================================================

        print_banner("Initial reset and reset release");

        #1ps;
        check_reset_outputs();

        // Keep reset active through one synchronized clock edge.
        sync();
        check_cycle();

        // resetb deassertion is synchronized.
        resetb = 1'b1;


        //======================================================================
        // TEST 2: Positive kernel coefficients and pipeline timing
        //======================================================================

        print_banner("Positive coefficients and pipeline timing");

        sync();
        check_cycle();
        apply_kernel(8'sd1, 8'sd2, 8'sd3);

        sync();
        check_cycle();
        apply_pixel(8'd10);

        sync();
        check_cycle();
        apply_pixel(8'd20);

        sync();
        check_cycle();
        apply_pixel(8'd30);

        sync();
        check_cycle();
        apply_pixel(8'd40);

        sync();
        check_cycle();
        apply_pixel(8'd50);

        sync();
        check_cycle();
        apply_pixel(8'd60);

        // Flush the final expected results through the PE pipeline.
        sync();
        check_cycle();

        sync();
        check_cycle();


        //======================================================================
        // TEST 3: Signed edge-enhancement coefficients
        //
        // Uses {-1, 8, -1}, matching one row of the demonstration kernel.
        // Pixels above 127 verify that unsigned grayscale values remain
        // positive during multiplication by signed coefficients.
        //======================================================================

        print_banner("Negative coefficients and unsigned pixels above 127");

        sync();
        check_cycle();
        apply_kernel(-8'sd1, 8'sd8, -8'sd1);
        runtime_kernel_change_covered = 1'b1;

        sync();
        check_cycle();
        apply_pixel(8'd120);

        sync();
        check_cycle();
        apply_pixel(8'd200);

        sync();
        check_cycle();
        apply_pixel(8'd255);

        sync();
        check_cycle();
        apply_pixel(8'd180);

        sync();
        check_cycle();
        apply_pixel(8'd64);

        sync();
        check_cycle();

        sync();
        check_cycle();


        //======================================================================
        // TEST 4: Extreme signed kernel values
        //======================================================================

        print_banner("Extreme signed kernel values");

        sync();
        check_cycle();
        apply_kernel(-128, 127, -8'sd1);

        sync();
        check_cycle();
        apply_pixel(8'd255);

        sync();
        check_cycle();
        apply_pixel(8'd254);

        sync();
        check_cycle();
        apply_pixel(8'd1);

        sync();
        check_cycle();
        apply_pixel(8'd128);

        sync();
        check_cycle();

        sync();
        check_cycle();


        //======================================================================
        // TEST 5: Asynchronous reset during active operation
        //
        // resetb is asserted between clock edges. All registered outputs must
        // clear immediately, without waiting for the next posedge.
        //======================================================================

        print_banner("Asynchronous reset during active operation");

        sync();
        check_cycle();
        apply_pixel(8'd77);

        sync();
        check_cycle();
        apply_pixel(8'd99);

        sync();
        check_cycle();
        apply_pixel(8'd123);

        // sync() above returns just after a posedge.
        // Assert reset a quarter-cycle later to demonstrate asynchronous reset.
        #(CLK_PERIOD / 4);
        resetb = 1'b0;

        clear_golden_model();

        #1ps;
        check_reset_outputs();
        reset_covered = 1'b1;

        // Keep reset active through one clock edge and check again.
        sync();
        check_cycle();

        // Deassert reset only after a synchronized edge.
        resetb = 1'b1;


        //======================================================================
        // TEST 6: Operation after reset recovery
        //======================================================================

        print_banner("Operation after reset recovery");

        sync();
        check_cycle();
        apply_kernel(-8'sd1, 8'sd8, -8'sd1);

        sync();
        check_cycle();
        apply_pixel(8'd25);

        sync();
        check_cycle();
        apply_pixel(8'd50);

        sync();
        check_cycle();
        apply_pixel(8'd75);

        sync();
        check_cycle();
        apply_pixel(8'd100);

        sync();
        check_cycle();

        sync();
        check_cycle();


        //======================================================================
        // Coverage and final result
        //======================================================================

        check_coverage();

        $display("");
        $display("================================================================");
        $display("PE TESTBENCH SUMMARY");
        $display("Checks performed : %0d", check_count);
        $display("Errors detected   : %0d", error_count);

        if (error_count == 0)
            $display("RESULT            : PASS");
        else
            $display("RESULT            : FAIL");

        $display("================================================================");

        #20ns;
        $stop;
    end

endmodule
