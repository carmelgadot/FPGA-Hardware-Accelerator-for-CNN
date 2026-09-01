# ============================================================================
# wave_tb_output_buffer_mux.do - waveform layout for tb_output_buffer_mux.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_output_buffer_mux.
# ----------------------------------------------------------------------------
# What we will see
# - TB_Stimulus : buffer_data[0]..buffer_data[5], read_group_sel
# - DUT_Outputs : read_data[0]..read_data[2]
# - Golden Model: golden_group0/1, expected_read_data
# - Coverage    : group_covered, route_covered, errors
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_output_buffer_mux.do
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
set DUT_PATH rtl/output_buffer_mux.sv
set TB_PATH  tb/tb_output_buffer_mux.sv

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
vsim -wlf wlfs_output_buffer_mux.wlf work.tb_output_buffer_mux
restart -force

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
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix binary   sim:/tb_output_buffer_mux/read_group_sel
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(0\)
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(2\)
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(3\)
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(4\)
add wave -radix unsigned sim:/tb_output_buffer_mux/buffer_data\(5\)

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_output_buffer_mux/read_data\(0\)
add wave -radix unsigned sim:/tb_output_buffer_mux/read_data\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/read_data\(2\)

# =======================
# Independent golden model
# =======================
add wave -divider {Golden_Model}
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group0\(0\)
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group0\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group0\(2\)
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group1\(0\)
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group1\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/golden_group1\(2\)
add wave -radix unsigned sim:/tb_output_buffer_mux/expected_read_data\(0\)
add wave -radix unsigned sim:/tb_output_buffer_mux/expected_read_data\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/expected_read_data\(2\)

# =======================
# Coverage / status
# =======================
add wave -divider {Coverage_And_Status}
add wave -radix binary   sim:/tb_output_buffer_mux/group_covered\(0\)
add wave -radix binary   sim:/tb_output_buffer_mux/group_covered\(1\)
add wave -radix unsigned sim:/tb_output_buffer_mux/errors

update
wave zoom full

run -all
