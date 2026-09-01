# ============================================================================
# wave_tb_input_subsystem.do - waveform layout for tb_input_subsystem.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_input_subsystem.
#
# What we will see
# - Clock_Reset_Input : clk, resetb, data_valid, frame_done, data
# - DUT_Outputs       : pixel_out[0..4], rd_valid
# - Subsystem_Control : wr_addr, rd_addr, BRAM read/write enables,
#                       row selectors and row padding
# - Controller_Debug  : FSM/control signals and buffer-control state
# - Coverage          : directed coverage flags, check_count, error_count
#
# How to use (ModelSim)
#   do do_files/wave_tb_input_subsystem.do
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
set FSM_PATH                 rtl/window_manager_fsm.sv
set BUFFER_CONTROL_PATH      rtl/buffer_control.sv
set CONTROLLER_PATH          rtl/row_buffer_controller.sv
set INPUT_BUFFERS_PATH       rtl/input_buffers.sv
set ROW_BUFFER_MUX_PATH      rtl/row_buffer_mux.sv
set ROW_BUFFER_BANK_PATH     rtl/row_buffer_bank.sv
set DUT_PATH                 rtl/input_subsystem.sv
set TB_PATH                  tb/tb_input_subsystem.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================

if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf
vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

# ============================================================================
# Compile DUT hierarchy and Testbench
# ============================================================================

vlog -sv \
    $BRAM_PATH \
    $COUNTER_PATH \
    $FSM_PATH \
    $BUFFER_CONTROL_PATH \
    $CONTROLLER_PATH \
    $INPUT_BUFFERS_PATH \
    $ROW_BUFFER_MUX_PATH \
    $ROW_BUFFER_BANK_PATH \
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
vsim -L altera_mf -voptargs=+acc -wlf wlfs_input_subsystem.wlf work.tb_input_subsystem
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

# =======================
# Clock / Reset / Input
# =======================
add wave -divider {Clock_Reset_Input}
add wave -radix binary   sim:/tb_input_subsystem/clk
add wave -radix binary   sim:/tb_input_subsystem/resetb
add wave -radix binary   sim:/tb_input_subsystem/data_valid
add wave -radix binary   sim:/tb_input_subsystem/frame_done
add wave -radix unsigned sim:/tb_input_subsystem/data

# =======================
# External DUT Outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix binary   sim:/tb_input_subsystem/rd_valid
add wave -radix unsigned sim:/tb_input_subsystem/pixel_out\(0\)
add wave -radix unsigned sim:/tb_input_subsystem/pixel_out\(1\)
add wave -radix unsigned sim:/tb_input_subsystem/pixel_out\(2\)
add wave -radix unsigned sim:/tb_input_subsystem/pixel_out\(3\)
add wave -radix unsigned sim:/tb_input_subsystem/pixel_out\(4\)

# =======================
# Input subsystem internal control
# =======================
add wave -divider {Subsystem_Internal_Control}
add wave -radix unsigned sim:/tb_input_subsystem/dut/wr_addr
add wave -radix unsigned sim:/tb_input_subsystem/dut/rd_addr
add wave -radix binary   sim:/tb_input_subsystem/dut/bram_wr_en
add wave -radix binary   sim:/tb_input_subsystem/dut/bram_rd_en
add wave -radix binary   sim:/tb_input_subsystem/dut/row_padding

# =======================
# Row selectors
# =======================
add wave -divider {Row_Selectors}
add wave -radix binary sim:/tb_input_subsystem/dut/row_sel\(0\)
add wave -radix binary sim:/tb_input_subsystem/dut/row_sel\(1\)
add wave -radix binary sim:/tb_input_subsystem/dut/row_sel\(2\)
add wave -radix binary sim:/tb_input_subsystem/dut/row_sel\(3\)
add wave -radix binary sim:/tb_input_subsystem/dut/row_sel\(4\)

# =======================
# Controller debug
# =======================
add wave -divider {Controller_Debug}
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/en_write_row
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/en_process_window
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/advance_window
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/frame_switch
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/next_row_ready
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/write_blocked
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/last_window
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/wr_valid
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/rd_valid
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/row_write_done
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/process_done

# =======================
# Buffer-control internals
# =======================
add wave -divider {Buffer_Control}
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/u_buffer_control/fill_buffer_onehot
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/u_buffer_control/top_buffer_onehot
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/u_buffer_control/padding_mask
add wave -radix unsigned sim:/tb_input_subsystem/dut/u_row_buffer_controller/u_buffer_control/occupied_rows
add wave -radix binary   sim:/tb_input_subsystem/dut/u_row_buffer_controller/u_buffer_control/active_read_mask

# =======================
# Coverage / status
# =======================
add wave -divider {Coverage_And_Status}
add wave -radix binary   sim:/tb_input_subsystem/async_reset_covered
add wave -radix binary   sim:/tb_input_subsystem/initial_fill_no_read_covered
add wave -radix binary   sim:/tb_input_subsystem/data_valid_gap_covered
add wave -radix binary   sim:/tb_input_subsystem/first_window_covered
add wave -radix binary   sim:/tb_input_subsystem/parallel_rows_covered
add wave -radix binary   sim:/tb_input_subsystem/bram_latency_covered
add wave -radix binary   sim:/tb_input_subsystem/stride_advance_covered
add wave -radix binary   sim:/tb_input_subsystem/second_window_covered
add wave -radix binary   sim:/tb_input_subsystem/reset_recovery_covered
add wave -radix unsigned sim:/tb_input_subsystem/check_count
add wave -radix unsigned sim:/tb_input_subsystem/error_count

update
run -all
wave zoom full
