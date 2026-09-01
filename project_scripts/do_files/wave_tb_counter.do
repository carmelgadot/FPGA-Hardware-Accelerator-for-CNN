# ============================================================================
# wave_tb_counter.do - waveform layout for tb_counter.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for tb_counter.
#
# The testbench includes:
#   - Asynchronous active-low reset
#   - Disabled counter hold
#   - Normal counting
#   - Pause and resume
#   - Synchronous clear
#   - Clear priority over enable
#   - Counter wrap-around
#   - Asynchronous reset during active operation
#   - Independent event-count golden model
#
# Golden-model principle:
#   Expected values are derived from the number of accepted increment events
#   modulo 2^WIDTH. The testbench does not reproduce the DUT always_ff block.
#
# How to use (ModelSim)
#   do do_files/wave_tb_counter.do
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

set DUT_PATH rtl/counter.sv
set TB_PATH  tb/tb_counter.sv

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
vsim -wlf wlfs_counter.wlf work.tb_counter
restart -force

catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================

configure wave -namecolwidth 300
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Clock / Reset
# =======================

add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/tb_counter/clk
add wave -radix binary sim:/tb_counter/resetb

# =======================
# DUT Inputs
# =======================

add wave -divider {DUT_Inputs}
add wave -radix binary sim:/tb_counter/en
add wave -radix binary sim:/tb_counter/clr

# =======================
# DUT Output
# =======================

add wave -divider {DUT_Output}
add wave -radix unsigned sim:/tb_counter/count

# =======================
# Independent Golden Model
# =======================

add wave -divider {Golden_Model}
add wave -radix unsigned sim:/tb_counter/increment_events

# =======================
# Scoreboard
# =======================

add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_counter/check_count
add wave -radix unsigned sim:/tb_counter/error_count

# =======================
# Coverage
# =======================

add wave -divider {Coverage}
add wave -radix binary sim:/tb_counter/reset_covered
add wave -radix binary sim:/tb_counter/hold_covered
add wave -radix binary sim:/tb_counter/count_covered
add wave -radix binary sim:/tb_counter/pause_resume_covered
add wave -radix binary sim:/tb_counter/clear_covered
add wave -radix binary sim:/tb_counter/clear_priority_covered
add wave -radix binary sim:/tb_counter/wrap_covered
add wave -radix binary sim:/tb_counter/mid_operation_reset_covered

# ============================================================================
# Run
# ============================================================================

run -all
wave zoom full
