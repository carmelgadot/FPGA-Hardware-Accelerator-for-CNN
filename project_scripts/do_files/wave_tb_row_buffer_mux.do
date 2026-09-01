# ============================================================================
# wave_tb_row_buffer_mux.do - waveform layout for tb_row_buffer_mux.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_row_buffer_mux.
#
# The DUT is purely combinational, therefore no clock/reset signals are needed.
# The testbench checks all valid one-hot routing combinations,
# invalid selector values, and data propagation through fixed selections.
# ----------------------------------------------------------------------------
# What we will see
# - Buffer_Data      : buffer_data[0]..buffer_data[NUM_BUFFERS-1]
# - Row_Selectors    : row_sel[0]..row_sel[INIT_ROWS-1], row_padding
# - DUT_Outputs      : pixel_out[0]..pixel_out[INIT_ROWS-1]
# - Scoreboard       : errors, combinations_tested, invalid_tests_tested
# ----------------------------------------------------------------------------
# Default configuration
# - NUM_BUFFERS = 8
# - INIT_ROWS   = 5
# - Total valid selector combinations = 8^5 = 32768
# - Total row-to-BRAM routing options = 5*8 = 40
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_row_buffer_mux.do
# ============================================================================

onerror {resume}
quietly set NumericStdNoWarnings 1
quietly set StdArithNoWarnings 1
quietly WaveActivateNextPane {} 0

# --- Build: create work library ---
if {![file exists work]} { vlib work }
vmap work work

# ============================================================================
# Path setup - adjust to your folder structure
# ============================================================================
set DUT_PATH rtl/row_buffer_mux.sv
set TB_PATH  tb/tb_row_buffer_mux.sv

# ============================================================================
# Compile DUT and Testbench
# ============================================================================
vlog -sv $DUT_PATH $TB_PATH

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
vsim -wlf wlfs_row_buffer_mux.wlf work.tb_row_buffer_mux
restart -force

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 300
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Physical BRAM outputs
# =======================
add wave -divider {Buffer_Data}
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(0\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(1\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(2\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(3\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(4\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(5\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(6\)
add wave -radix unsigned sim:/tb_row_buffer_mux/buffer_data\(7\)

# =======================
# One-hot row selectors
# =======================
add wave -divider {Row_Selectors}
add wave -radix binary sim:/tb_row_buffer_mux/row_sel\(0\)
add wave -radix binary sim:/tb_row_buffer_mux/row_sel\(1\)
add wave -radix binary sim:/tb_row_buffer_mux/row_sel\(2\)
add wave -radix binary sim:/tb_row_buffer_mux/row_sel\(3\)
add wave -radix binary sim:/tb_row_buffer_mux/row_sel\(4\)
add wave -radix binary sim:/tb_row_buffer_mux/row_padding

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_row_buffer_mux/pixel_out\(0\)
add wave -radix unsigned sim:/tb_row_buffer_mux/pixel_out\(1\)
add wave -radix unsigned sim:/tb_row_buffer_mux/pixel_out\(2\)
add wave -radix unsigned sim:/tb_row_buffer_mux/pixel_out\(3\)
add wave -radix unsigned sim:/tb_row_buffer_mux/pixel_out\(4\)

# =======================
# Scoreboard / TB counters
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_row_buffer_mux/combinations_tested
add wave -radix unsigned sim:/tb_row_buffer_mux/invalid_tests_tested
add wave -radix unsigned sim:/tb_row_buffer_mux/errors

# =======================
# DUT view
# =======================
# The DUT has no sequential internal state. Its complete functionality can be
# observed through buffer_data, row_sel and pixel_out.
add wave -divider {DUT}
add wave -radix unsigned sim:/tb_row_buffer_mux/dut/buffer_data\(0\)
add wave -radix binary sim:/tb_row_buffer_mux/dut/row_sel\(0\)
add wave -radix unsigned sim:/tb_row_buffer_mux/dut/pixel_out\(0\)

update
wave zoom full

# Always run to completion
run -all