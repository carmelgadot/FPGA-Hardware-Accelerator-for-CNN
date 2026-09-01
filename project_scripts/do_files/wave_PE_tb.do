# ============================================================================
# wave_PE_tb.do - waveform layout for PE_tb.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for PE_tb.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset   : clk, resetb
# - TB_Stimulus       : pixel, K0, K1, K2
# - DUT_Pixels        : pixel0, pixel1, pixel2, row_shift_reg
# - DUT_MAC_Outputs   : mul0, mul1, mul2, sum
# - Reference_Model   : history0..2, expected_sum_delayed, validity tracking
# - Scoreboard        : error_count, check_count
# - Coverage          : reset/kernel/pixel/runtime-change coverage flags
# - DUT_Internal      : pixel0_signed, pixel1_signed, pixel2_signed
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_PE_tb.do
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
set DUT_PATH rtl/PE.sv
set TB_PATH  tb/PE_tb.sv

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
vsim -wlf wlfs_PE.wlf work.PE_tb
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
# Clock and reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/PE_tb/clk
add wave -radix binary sim:/PE_tb/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix unsigned sim:/PE_tb/pixel
add wave -radix decimal  sim:/PE_tb/K0
add wave -radix decimal  sim:/PE_tb/K1
add wave -radix decimal  sim:/PE_tb/K2

# =======================
# DUT pixel window
# =======================
add wave -divider {DUT_Pixels}
add wave -radix unsigned sim:/PE_tb/pixel0
add wave -radix unsigned sim:/PE_tb/pixel1
add wave -radix unsigned sim:/PE_tb/pixel2
add wave -radix hexadecimal sim:/PE_tb/row_shift_reg

# =======================
# DUT multiply-accumulate outputs
# =======================
add wave -divider {DUT_MAC_Outputs}
add wave -radix decimal sim:/PE_tb/mul0
add wave -radix decimal sim:/PE_tb/mul1
add wave -radix decimal sim:/PE_tb/mul2
add wave -radix decimal sim:/PE_tb/sum

# =======================
# Reference model
# =======================
add wave -divider {Reference_Model}
add wave -radix unsigned sim:/PE_tb/history0
add wave -radix unsigned sim:/PE_tb/history1
add wave -radix unsigned sim:/PE_tb/history2
add wave -radix decimal  sim:/PE_tb/expected_sum_delayed
add wave -radix unsigned sim:/PE_tb/captured_pixel_count
add wave -radix binary   sim:/PE_tb/expected_sum_valid

# =======================
# Scoreboard / TB counters
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/PE_tb/error_count
add wave -radix unsigned sim:/PE_tb/check_count

# =======================
# Coverage tracking
# =======================
add wave -divider {Coverage}
add wave -radix binary sim:/PE_tb/reset_covered
add wave -radix binary sim:/PE_tb/positive_kernel_covered
add wave -radix binary sim:/PE_tb/negative_kernel_covered
add wave -radix binary sim:/PE_tb/high_unsigned_pixel_covered
add wave -radix binary sim:/PE_tb/runtime_kernel_change_covered
add wave -radix binary sim:/PE_tb/minimum_kernel_value_covered
add wave -radix binary sim:/PE_tb/maximum_kernel_value_covered
add wave -radix binary sim:/PE_tb/full_window_covered
add wave -radix binary sim:/PE_tb/pipeline_latency_covered

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal}
add wave -radix decimal sim:/PE_tb/dut/pixel0_signed
add wave -radix decimal sim:/PE_tb/dut/pixel1_signed
add wave -radix decimal sim:/PE_tb/dut/pixel2_signed

update
wave zoom full

# Always run to completion
run -all
