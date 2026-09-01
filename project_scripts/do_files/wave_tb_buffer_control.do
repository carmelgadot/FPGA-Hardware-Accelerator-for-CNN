# ============================================================================
# wave_tb_buffer_control.do - waveform layout for tb_buffer_control.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for tb_buffer_control.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : row_write_done, advance_window, frame_done, frame_switch, wr_valid, rd_valid
# - DUT_Outputs     : next_row_ready, write_blocked, bram_wr_en, bram_rd_en,
#                     row_sel[0]..row_sel[INIT_ROWS-1], row_padding
# - Scoreboard      : error_count, check_count
# - DUT_Internal    : fill_buffer_onehot, top_buffer_onehot, padding_mask,
#                     occupied_rows, active_read_mask
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_buffer_control.do
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
set DUT_PATH rtl/buffer_control.sv
set TB_PATH  tb/tb_buffer_control.sv

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
vsim -wlf wlfs_buffer_control.wlf work.tb_buffer_control
restart -force

# Remove wave signals left from previous simulations
catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 280
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Top-level TB signals
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/tb_buffer_control/clk
add wave -radix binary sim:/tb_buffer_control/resetb

add wave -divider {TB_Stimulus}
add wave -radix binary sim:/tb_buffer_control/row_write_done
add wave -radix binary sim:/tb_buffer_control/advance_window
add wave -radix binary sim:/tb_buffer_control/frame_done
add wave -radix binary sim:/tb_buffer_control/frame_switch
add wave -radix binary sim:/tb_buffer_control/wr_valid
add wave -radix binary sim:/tb_buffer_control/rd_valid

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix binary sim:/tb_buffer_control/next_row_ready
add wave -radix binary sim:/tb_buffer_control/write_blocked
add wave -radix binary sim:/tb_buffer_control/last_window
add wave -radix binary sim:/tb_buffer_control/bram_wr_en
add wave -radix binary sim:/tb_buffer_control/bram_rd_en

add wave -divider {Row_Selectors}
add wave -radix binary sim:/tb_buffer_control/row_sel\(0\)
add wave -radix binary sim:/tb_buffer_control/row_sel\(1\)
add wave -radix binary sim:/tb_buffer_control/row_sel\(2\)
add wave -radix binary sim:/tb_buffer_control/row_sel\(3\)
add wave -radix binary sim:/tb_buffer_control/row_sel\(4\)
add wave -radix binary sim:/tb_buffer_control/row_padding

# =======================
# Scoreboard / TB counters
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_buffer_control/error_count
add wave -radix unsigned sim:/tb_buffer_control/check_count

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal}
add wave -radix binary sim:/tb_buffer_control/dut/fill_buffer_onehot
add wave -radix binary sim:/tb_buffer_control/dut/top_buffer_onehot
add wave -radix binary sim:/tb_buffer_control/dut/next_frame_start_onehot
add wave -radix binary sim:/tb_buffer_control/dut/frame_boundary_valid
add wave -radix binary sim:/tb_buffer_control/dut/padding_mask
add wave -radix unsigned sim:/tb_buffer_control/dut/occupied_rows
add wave -radix binary sim:/tb_buffer_control/dut/active_read_mask

update
wave zoom full

# Always run to completion
run -all
