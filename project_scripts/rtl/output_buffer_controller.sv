/*==============================================================================
  Module: output_buffer_controller
  Purpose:
    Controls address generation and BRAM enables for the two-group output
    ping-pong buffer.

    The controller receives conv_valid aligned with the three parallel
    convolution results. It writes each valid result set into the active output
    group and independently reads the previously completed group.

    Internal modules:
      1) output_buffer_fsm
         - Selects the active write and read groups.
         - Separates parallel, write-only, and wait-read operating phases.

      2) Write address counter
         - Advances only when a valid convolution result is accepted.
         - Clears after the final output address is written.

      3) Read address counter
         - Advances for each BRAM read request.
         - Clears immediately after the final read request is issued.

    BRAM read timing:
      - The output BRAM has a registered read path.
      - rd_valid is delayed by BRAM_READ_LATENCY clocks to generate out_valid.
      - After the final read request, further reads are blocked while the final
        BRAM data propagates through the read pipeline.
      - read_done is asserted only after that final read has propagated. This
        keeps the FSM on the same read group until the group is safe to reuse.



  Group mapping for the default 6-buffer / 3-output configuration:
    ---------------------------------------------------------------------------
    group 0 : BRAM0, BRAM1, BRAM2
    group 1 : BRAM3, BRAM4, BRAM5
    ---------------------------------------------------------------------------

  Notes:
    - NUM_OUTPUT_BUFFERS is expected to equal 2*PARALLEL_OUTPUTS.
    - BRAM_READ_LATENCY must be at least 1.
    - No backpressure is generated toward conv_core. System scheduling must
      ensure conv_valid is not asserted while the FSM has disabled writing.
==============================================================================*/

module output_buffer_controller #(
    parameter int OUTPUT_LENGTH       = 640,
    parameter int ADDR_WIDTH          = 10,
    parameter int NUM_OUTPUT_BUFFERS  = 6,
    parameter int PARALLEL_OUTPUTS    = 3,
    parameter int BRAM_READ_LATENCY   = 2
)(
    input  logic                            clk,               // System clock
    input  logic                            resetb,            // Asynchronous active-low reset
    input  logic                            conv_valid,        // conv_core outputs are valid this cycle

    output logic [ADDR_WIDTH-1:0]           wr_addr,           // Output-BRAM write address
    output logic [ADDR_WIDTH-1:0]           rd_addr,           // Output-BRAM read address

    output logic [NUM_OUTPUT_BUFFERS-1:0]   bram_wr_en,        // One write-enable bit per physical BRAM
    output logic [NUM_OUTPUT_BUFFERS-1:0]   bram_rd_en,        // One read-enable bit per physical BRAM

    output logic                            read_group_sel,    // Group selected by output_buffer_mux
    output logic                            out_valid          // read_data is valid this cycle
);


    //--------------------------------------------------------------------------
    // FSM control signals
    //--------------------------------------------------------------------------
    logic en_write;                 // Active write group may accept convolution results
    logic en_read;                  // Active read group may issue BRAM reads
    logic write_group_sel;          // 0: group 0, 1: group 1
    logic fsm_read_group_sel;       // Read group selected by the FSM


    //--------------------------------------------------------------------------
    // Write-side control
    //--------------------------------------------------------------------------
    logic wr_valid;                 // Actual output-BRAM write operation
    logic write_done;               // Final address of active write group is written


    //--------------------------------------------------------------------------
    // Read-side control
    //--------------------------------------------------------------------------
    logic rd_valid;                 // Actual output-BRAM read request
    logic last_read_issued;         // Final read address of active group is issued
    logic read_pending;             // Final read is propagating through BRAM pipeline
    logic read_done;                // Final read has propagated; group is safe to reuse

    logic [BRAM_READ_LATENCY-1:0] read_valid_pipe;
    logic [BRAM_READ_LATENCY-1:0] last_read_pipe;

    integer pipe_idx;
    integer buffer_idx;


    //==========================================================================
    // Output Buffer FSM
    //
    // Selects which three-BRAM group is written and which is read. read_done is
    // delayed until the final BRAM data has propagated, so the selected read
    // group remains stable for the complete read-data lifetime.
    //==========================================================================

    output_buffer_fsm u_output_buffer_fsm (
        .clk             (clk),
        .resetb          (resetb),
        .write_done      (write_done),
        .read_done       (read_done),
        .en_write        (en_write),
        .en_read         (en_read),
        .write_group_sel (write_group_sel),
        .read_group_sel  (fsm_read_group_sel)
    );

    assign read_group_sel = fsm_read_group_sel;


    //==========================================================================
    // Write Control
    //==========================================================================

    // A write occurs only when the FSM allows writing and the current
    // convolution outputs are valid.
    assign wr_valid = en_write && conv_valid;

    // Assert during the cycle in which the final location of the active group
    // is written.
    assign write_done =
        wr_valid &&
        (wr_addr == OUTPUT_LENGTH-1);


    //==========================================================================
    // Write Address Counter
    //==========================================================================

    counter #(
        .WIDTH (ADDR_WIDTH)
    ) u_write_counter (
        .clk    (clk),
        .resetb (resetb),
        .en     (wr_valid),
        .clr    (write_done),
        .count  (wr_addr)
    );


    //==========================================================================
    // Read Control
    //==========================================================================

    // Read continuously while the FSM enables the active read group. Once the
    // final request is issued, block new requests until its data has drained.
    assign rd_valid = en_read && ~read_pending;

    // Assert during the cycle in which the final address is requested.
    assign last_read_issued =
        rd_valid &&
        (rd_addr == OUTPUT_LENGTH-1);


    //==========================================================================
    // Read Address Counter
    //==========================================================================

    counter #(
        .WIDTH (ADDR_WIDTH)
    ) u_read_counter (
        .clk    (clk),
        .resetb (resetb),
        .en     (rd_valid),
        .clr    (last_read_issued),
        .count  (rd_addr)
    );


    //==========================================================================
    // BRAM Read-Latency Tracking
    //
    // read_valid_pipe aligns out_valid with the registered BRAM data.
    // last_read_pipe delays the final-read marker by the same latency so the
    // FSM releases the read group only after its final data is available.
    //==========================================================================

    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb) begin
            read_valid_pipe <= '0;
            last_read_pipe  <= '0;
        end
        else begin
            read_valid_pipe[0] <= rd_valid;
            last_read_pipe[0]  <= last_read_issued;

            for (pipe_idx = 1; pipe_idx < BRAM_READ_LATENCY; pipe_idx = pipe_idx + 1) begin
                read_valid_pipe[pipe_idx] <= read_valid_pipe[pipe_idx-1];
                last_read_pipe[pipe_idx]  <= last_read_pipe[pipe_idx-1];
            end
        end
    end

    assign out_valid = read_valid_pipe[BRAM_READ_LATENCY-1];
    assign read_done = last_read_pipe[BRAM_READ_LATENCY-1];


    // Keep reads blocked from the final request until read_done is consumed.
    always_ff @(posedge clk or negedge resetb) begin
        if (~resetb)
            read_pending <= 1'b0;
        else begin
            if (read_done)
                read_pending <= 1'b0;
            else if (last_read_issued)
                read_pending <= 1'b1;
        end
    end


    //==========================================================================
    // Physical BRAM Enable Generation
    //
    // All PARALLEL_OUTPUTS BRAMs belonging to the selected group are enabled
    // together. The two groups are physically independent and may therefore be
    // written and read simultaneously.
    //==========================================================================

    always_comb begin
        bram_wr_en = '0;
        bram_rd_en = '0;

        for (buffer_idx = 0; buffer_idx < PARALLEL_OUTPUTS; buffer_idx = buffer_idx + 1) begin
            if (wr_valid) begin
                if (write_group_sel)
                    bram_wr_en[buffer_idx + PARALLEL_OUTPUTS] = 1'b1;
                else
                    bram_wr_en[buffer_idx] = 1'b1;
            end

            if (rd_valid) begin
                if (fsm_read_group_sel)
                    bram_rd_en[buffer_idx + PARALLEL_OUTPUTS] = 1'b1;
                else
                    bram_rd_en[buffer_idx] = 1'b1;
            end
        end
    end


endmodule
