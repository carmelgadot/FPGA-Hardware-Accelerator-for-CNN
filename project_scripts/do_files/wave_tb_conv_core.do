# ============================================================================
# wave_tb_conv_core_independent.do - waveform layout for tb_conv_core_independent.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for the independent-golden-model conv_core testbench.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - Input_Pixels    : input_pixel0..input_pixel4
# - Kernel          : kernel[0]..kernel[8]
# - DUT_Outputs     : data_out0, data_out1, data_out2
# - Convolution     : sum_out0_comb, sum_out1_comb, sum_out2_comb
# - Post_Processing : data_out0_comb, data_out1_comb, data_out2_comb
# - PE_Sums         : pe_sum[0]..pe_sum[8]
# - Scoreboard      : error_count, check_count
# - Coverage        : functional coverage flags
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_conv_core.do
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
set PE_PATH  rtl/PE.sv
set DUT_PATH rtl/conv_core.sv
set TB_PATH  tb/tb_conv_core.sv

# ============================================================================
# Compile PE, DUT and Testbench
# ============================================================================
vlog -sv $PE_PATH $DUT_PATH $TB_PATH

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
vsim -wlf wlfs_conv_core.wlf work.tb_conv_core
restart -force

# Remove wave signals left from previous simulations
catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 300
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Clock / Reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/tb_conv_core/clk
add wave -radix binary sim:/tb_conv_core/resetb

# =======================
# Input pixels
# =======================
add wave -divider {Input_Pixels}
add wave -radix unsigned sim:/tb_conv_core/input_pixel0
add wave -radix unsigned sim:/tb_conv_core/input_pixel1
add wave -radix unsigned sim:/tb_conv_core/input_pixel2
add wave -radix unsigned sim:/tb_conv_core/input_pixel3
add wave -radix unsigned sim:/tb_conv_core/input_pixel4

# =======================
# Runtime kernel
# =======================
add wave -divider {Kernel}
add wave -radix decimal sim:/tb_conv_core/kernel\(0\)
add wave -radix decimal sim:/tb_conv_core/kernel\(1\)
add wave -radix decimal sim:/tb_conv_core/kernel\(2\)
add wave -radix decimal sim:/tb_conv_core/kernel\(3\)
add wave -radix decimal sim:/tb_conv_core/kernel\(4\)
add wave -radix decimal sim:/tb_conv_core/kernel\(5\)
add wave -radix decimal sim:/tb_conv_core/kernel\(6\)
add wave -radix decimal sim:/tb_conv_core/kernel\(7\)
add wave -radix decimal sim:/tb_conv_core/kernel\(8\)

# =======================
# Final DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_conv_core/data_out0
add wave -radix unsigned sim:/tb_conv_core/data_out1
add wave -radix unsigned sim:/tb_conv_core/data_out2

# =======================
# Raw 3x3 convolution sums
# =======================
add wave -divider {Convolution_Sums}
add wave -radix decimal sim:/tb_conv_core/dut/sum_out0_comb
add wave -radix decimal sim:/tb_conv_core/dut/sum_out1_comb
add wave -radix decimal sim:/tb_conv_core/dut/sum_out2_comb

# =======================
# Post-processing results before output register
# =======================
add wave -divider {Post_Processing}
add wave -radix unsigned sim:/tb_conv_core/dut/data_out0_comb
add wave -radix unsigned sim:/tb_conv_core/dut/data_out1_comb
add wave -radix unsigned sim:/tb_conv_core/dut/data_out2_comb

# =======================
# Individual PE sums
# =======================
add wave -divider {PE_Sums}
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(0\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(1\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(2\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(3\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(4\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(5\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(6\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(7\)
add wave -radix decimal sim:/tb_conv_core/dut/pe_sum\(8\)

# =======================
# Reference expected-output pipelines
# =======================
add wave -divider {Reference_Model}
add wave -radix unsigned sim:/tb_conv_core/expected_pipe0\(2\)
add wave -radix unsigned sim:/tb_conv_core/expected_pipe1\(2\)
add wave -radix unsigned sim:/tb_conv_core/expected_pipe2\(2\)

# =======================
# Scoreboard
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_conv_core/error_count
add wave -radix unsigned sim:/tb_conv_core/check_count

# =======================
# Coverage
# =======================
add wave -divider {Coverage}
add wave -radix binary sim:/tb_conv_core/reset_covered
add wave -radix binary sim:/tb_conv_core/signed_kernel_covered
add wave -radix binary sim:/tb_conv_core/high_unsigned_pixel_covered
add wave -radix binary sim:/tb_conv_core/no_saturation_covered
add wave -radix binary sim:/tb_conv_core/low_saturation_covered
add wave -radix binary sim:/tb_conv_core/high_saturation_covered

# Per-output coverage
add wave -radix binary sim:/tb_conv_core/output_checked\(0\)
add wave -radix binary sim:/tb_conv_core/output_checked\(1\)
add wave -radix binary sim:/tb_conv_core/output_checked\(2\)

# Per-kernel-position coverage
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(0\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(1\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(2\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(3\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(4\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(5\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(6\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(7\)
add wave -radix binary sim:/tb_conv_core/kernel_position_covered\(8\)

update
wave zoom full

# Always run to completion
run -all
