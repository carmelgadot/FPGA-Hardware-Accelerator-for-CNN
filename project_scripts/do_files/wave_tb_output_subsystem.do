# ============================================================================
# wave_tb_output_subsystem.do - waveform layout for tb_output_subsystem.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_output_subsystem.
#
# The testbench uses an independent external transaction-list golden model.
# It does not duplicate the output-buffer FSM, counters, address generation,
# BRAM-enable logic, or group-selection logic.
#
# What we will see
# - Clock_Reset_Input : clk, resetb, conv_valid, data_in[0..2]
# - DUT_Outputs       : read_data[0..2], out_valid
# - Controller_Debug  : addresses, BRAM enables, group selection
# - FSM_Debug         : controller FSM state and control outputs
# - Golden_Model      : expected / received transaction counts
# - Coverage          : directed coverage flags and error count
#
# How to use (ModelSim)
#   do do_files/wave_tb_output_subsystem.do
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

set QUARTUS_SIM_LIB          "C:/Users/modelsim/modelsim_ase/altera/verilog/src"

set BRAM_PATH                rtl/BRAM.v
set COUNTER_PATH             rtl/counter.sv
set OUTPUT_FSM_PATH          rtl/output_buffer_fsm.sv
set OUTPUT_CONTROLLER_PATH   rtl/output_buffer_controller.sv
set OUTPUT_BUFFERS_PATH      rtl/output_buffers.sv
set OUTPUT_MUX_PATH          rtl/output_buffer_mux.sv
set OUTPUT_BANK_PATH         rtl/output_buffer_bank.sv
set DUT_PATH                 rtl/output_subsystem.sv
set TB_PATH                  tb/tb_output_subsystem.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================

if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf

# BRAM IP uses altsyncram, which is defined in altera_mf.v.
vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

# ============================================================================
# Compile DUT hierarchy and testbench
# ============================================================================

vlog -sv \
    $BRAM_PATH \
    $COUNTER_PATH \
    $OUTPUT_FSM_PATH \
    $OUTPUT_CONTROLLER_PATH \
    $OUTPUT_BUFFERS_PATH \
    $OUTPUT_MUX_PATH \
    $OUTPUT_BANK_PATH \
    $DUT_PATH \
    $TB_PATH

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
vsim -L altera_mf -voptargs=+acc -wlf wlfs_output_subsystem.wlf work.tb_output_subsystem
restart -force

catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================

configure wave -namecolwidth 320
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
add wave -radix binary   sim:/tb_output_subsystem/clk
add wave -radix binary   sim:/tb_output_subsystem/resetb
add wave -radix binary   sim:/tb_output_subsystem/conv_valid
add wave -radix unsigned sim:/tb_output_subsystem/data_in\(0\)
add wave -radix unsigned sim:/tb_output_subsystem/data_in\(1\)
add wave -radix unsigned sim:/tb_output_subsystem/data_in\(2\)

# =======================
# External DUT Outputs
# =======================

add wave -divider {DUT_Outputs}
add wave -radix binary   sim:/tb_output_subsystem/out_valid
add wave -radix unsigned sim:/tb_output_subsystem/read_data\(0\)
add wave -radix unsigned sim:/tb_output_subsystem/read_data\(1\)
add wave -radix unsigned sim:/tb_output_subsystem/read_data\(2\)

# =======================
# Output Subsystem Internal Control
# =======================

add wave -divider {Subsystem_Internal_Control}
add wave -radix unsigned sim:/tb_output_subsystem/dut/wr_addr
add wave -radix unsigned sim:/tb_output_subsystem/dut/rd_addr
add wave -radix binary   sim:/tb_output_subsystem/dut/bram_wr_en
add wave -radix binary   sim:/tb_output_subsystem/dut/bram_rd_en
add wave -radix binary   sim:/tb_output_subsystem/dut/read_group_sel

# =======================
# Controller Debug
# =======================

add wave -divider {Controller_Debug}
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/en_write
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/en_read
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/write_group_sel
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/fsm_read_group_sel
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/wr_valid
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/write_done
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/rd_valid
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/last_read_issued
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/read_pending
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/read_done
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/read_valid_pipe
add wave -radix binary   sim:/tb_output_subsystem/dut/u_output_buffer_controller/last_read_pipe

# =======================
# FSM Debug
# =======================

add wave -divider {FSM_Debug}
add wave -radix FSM_STATE sim:/tb_output_subsystem/dut/u_output_buffer_controller/u_output_buffer_fsm/state
add wave -radix FSM_STATE sim:/tb_output_subsystem/dut/u_output_buffer_controller/u_output_buffer_fsm/next_state

# =======================
# Golden Model / Scoreboard
# =======================

add wave -divider {Golden_Model_Scoreboard}
add wave -radix unsigned sim:/tb_output_subsystem/expected_count
add wave -radix unsigned sim:/tb_output_subsystem/received_count
add wave -radix unsigned sim:/tb_output_subsystem/check_count
add wave -radix unsigned sim:/tb_output_subsystem/error_count

# =======================
# Coverage
# =======================

add wave -divider {Coverage}
add wave -radix binary sim:/tb_output_subsystem/async_reset_covered
add wave -radix binary sim:/tb_output_subsystem/initial_fill_no_output_covered
add wave -radix binary sim:/tb_output_subsystem/conv_valid_gap_covered
add wave -radix binary sim:/tb_output_subsystem/continuous_write_covered
add wave -radix binary sim:/tb_output_subsystem/first_group_read_covered
add wave -radix binary sim:/tb_output_subsystem/second_group_read_covered
add wave -radix binary sim:/tb_output_subsystem/group_reuse_covered
add wave -radix binary sim:/tb_output_subsystem/all_outputs_received_covered

# ============================================================================
# Run
# ============================================================================

run -all
wave zoom full
