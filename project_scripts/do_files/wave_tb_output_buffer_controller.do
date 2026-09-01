# ============================================================================
# wave_tb_output_buffer_controller.do
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_output_buffer_controller.
#
# The testbench includes:
#   - Asynchronous reset checks
#   - Initial group-0 fill
#   - conv_valid gaps and write-counter hold
#   - Parallel ping-pong write/read operation
#   - Read-finishes-first / WRITE_ONLY operation
#   - Write-finishes-first / WAIT_READ operation
#   - Simultaneous write/read completion
#   - BRAM read-latency / out_valid alignment
#   - Final-read drain with no extra read request
#   - Independent transaction-level golden model
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_output_buffer_controller.do
# ============================================================================

onerror {resume}
quietly set NumericStdNoWarnings 1
quietly set StdArithNoWarnings 1
quietly WaveActivateNextPane {} 0

# --- Build: create work library ---
if {![file exists work]} { vlib work }
vmap work work

# ============================================================================
# Path setup - adjust only if your folder structure is different
# ============================================================================
set COUNTER_PATH rtl/counter.sv
set FSM_PATH     rtl/output_buffer_fsm.sv
set DUT_PATH     rtl/output_buffer_controller.sv
set TB_PATH      tb/tb_output_buffer_controller.sv

# ============================================================================
# Compile DUT hierarchy and Testbench
# ============================================================================
vlog -sv $COUNTER_PATH $FSM_PATH $DUT_PATH $TB_PATH

# --- Keep UI calm ---
catch {pref set Editor auto_open 0}
catch {pref set editor.openonerror 0}
catch {pref set PrefMain OpenSourceOnError 0}
catch {pref set PrefSource OpenOnError 0}
catch {view -close source}
catch {view -hide source}
catch {pref set PrefCompile OpenSourceOnError 0}
catch {pref set PrefSource UseExternalEditor 1}
catch {pref set PrefSource ExternalEditor {}}
catch {pref set PrefSource OpenOnDoubleClick 0}
catch {view -close editor}

# ============================================================================
# Fresh simulation
# ============================================================================
catch {quit -sim}
vsim -wlf wlfs_output_buffer_controller.wlf work.tb_output_buffer_controller
restart -force

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 310
configure wave -valuecolwidth 160
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# ============================================================================
# FSM state names
# ============================================================================
radix define FSM_STATE {
    3'd0 "ST_FILL_GROUP0",
    3'd1 "ST_WRITE1_READ0",
    3'd2 "ST_WRITE1_ONLY",
    3'd3 "ST_WAIT_READ0",
    3'd4 "ST_WRITE0_READ1",
    3'd5 "ST_WRITE0_ONLY",
    3'd6 "ST_WAIT_READ1"
}

# =======================
# Clock / Reset / Input
# =======================
add wave -divider {Clock_Reset_Input}
add wave -radix binary   sim:/tb_output_buffer_controller/clk
add wave -radix binary   sim:/tb_output_buffer_controller/resetb
add wave -radix binary   sim:/tb_output_buffer_controller/conv_valid

# =======================
# External DUT outputs
# =======================
add wave -divider {Controller_Outputs}
add wave -radix unsigned sim:/tb_output_buffer_controller/wr_addr
add wave -radix unsigned sim:/tb_output_buffer_controller/rd_addr
add wave -radix binary   sim:/tb_output_buffer_controller/bram_wr_en
add wave -radix binary   sim:/tb_output_buffer_controller/bram_rd_en
add wave -radix binary   sim:/tb_output_buffer_controller/read_group_sel
add wave -radix binary   sim:/tb_output_buffer_controller/out_valid

# =======================
# Internal write control
# =======================
add wave -divider {Write_Control}
add wave -radix binary sim:/tb_output_buffer_controller/dut/en_write
add wave -radix binary sim:/tb_output_buffer_controller/dut/write_group_sel
add wave -radix binary sim:/tb_output_buffer_controller/dut/wr_valid
add wave -radix binary sim:/tb_output_buffer_controller/dut/write_done

# =======================
# Internal read control
# =======================
add wave -divider {Read_Control}
add wave -radix binary sim:/tb_output_buffer_controller/dut/en_read
add wave -radix binary sim:/tb_output_buffer_controller/dut/fsm_read_group_sel
add wave -radix binary sim:/tb_output_buffer_controller/dut/rd_valid
add wave -radix binary sim:/tb_output_buffer_controller/dut/last_read_issued
add wave -radix binary sim:/tb_output_buffer_controller/dut/read_pending
add wave -radix binary sim:/tb_output_buffer_controller/dut/read_done
add wave -radix binary sim:/tb_output_buffer_controller/dut/read_valid_pipe
add wave -radix binary sim:/tb_output_buffer_controller/dut/last_read_pipe

# =======================
# FSM
# =======================
add wave -divider {Output_Buffer_FSM}
add wave -radix FSM_STATE sim:/tb_output_buffer_controller/dut/u_output_buffer_fsm/state
add wave -radix FSM_STATE sim:/tb_output_buffer_controller/dut/u_output_buffer_fsm/next_state

# =======================
# Independent golden model
# =======================
add wave -divider {Golden_Model}
add wave -radix binary   sim:/tb_output_buffer_controller/ref_initial_fill
add wave -radix binary   sim:/tb_output_buffer_controller/ref_write_active
add wave -radix binary   sim:/tb_output_buffer_controller/ref_read_active
add wave -radix binary   sim:/tb_output_buffer_controller/ref_write_group
add wave -radix binary   sim:/tb_output_buffer_controller/ref_read_group
add wave -radix binary   sim:/tb_output_buffer_controller/ref_read_pending
add wave -radix unsigned sim:/tb_output_buffer_controller/ref_wr_addr
add wave -radix unsigned sim:/tb_output_buffer_controller/ref_rd_addr
add wave -radix binary   sim:/tb_output_buffer_controller/exp_wr_mask
add wave -radix binary   sim:/tb_output_buffer_controller/exp_rd_mask
add wave -radix binary   sim:/tb_output_buffer_controller/exp_out_valid

# =======================
# Scoreboard / Coverage
# =======================
add wave -divider {Scoreboard_Coverage}
add wave -radix decimal sim:/tb_output_buffer_controller/errors
add wave -radix decimal sim:/tb_output_buffer_controller/checks
add wave -radix binary  sim:/tb_output_buffer_controller/initial_fill_covered
add wave -radix binary  sim:/tb_output_buffer_controller/write_gap_covered
add wave -radix binary  sim:/tb_output_buffer_controller/parallel_rw_covered
add wave -radix binary  sim:/tb_output_buffer_controller/write_finishes_first_covered
add wave -radix binary  sim:/tb_output_buffer_controller/read_finishes_first_covered
add wave -radix binary  sim:/tb_output_buffer_controller/simultaneous_completion_covered
add wave -radix binary  sim:/tb_output_buffer_controller/read_drain_covered
add wave -radix binary  sim:/tb_output_buffer_controller/group0_write_covered
add wave -radix binary  sim:/tb_output_buffer_controller/group1_write_covered
add wave -radix binary  sim:/tb_output_buffer_controller/group0_read_covered
add wave -radix binary  sim:/tb_output_buffer_controller/group1_read_covered
add wave -radix binary  sim:/tb_output_buffer_controller/out_valid_latency_covered
add wave -radix binary  sim:/tb_output_buffer_controller/async_reset_covered

# ============================================================================
# Run
# ============================================================================
run -all
wave zoom full
