# ============================================================================
# wave_tb_output_buffer_bank.do - waveform layout for output_buffer_bank_tb.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# output_buffer_bank_tb.
# Includes Intel/Altera simulation library compilation for BRAM IP usage.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : rd_addr, wr_addr, data_in[0..2], wren, rden,
#                     read_group_sel
# - DUT_Outputs     : read_data[0..2]
# - DUT_Internal    : buffer_data[0..5]
# - Golden Model    : expected_read_data[0..2]
# - Coverage        : integration coverage flags and scoreboard
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_output_buffer_bank.do
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
set QUARTUS_SIM_LIB       "C:/Users/modelsim/modelsim_ase/altera/verilog/src"
set BRAM_PATH             rtl/BRAM.v
set OUTPUT_BUFFERS_PATH   rtl/output_buffers.sv
set OUTPUT_MUX_PATH       rtl/output_buffer_mux.sv
set DUT_PATH              rtl/output_buffer_bank.sv
set TB_PATH               tb/output_buffer_bank_tb.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================
if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf
vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

# ============================================================================
# Compile DUT dependencies, DUT and Testbench
# ============================================================================
vlog -sv $BRAM_PATH $OUTPUT_BUFFERS_PATH $OUTPUT_MUX_PATH $DUT_PATH $TB_PATH

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
vsim -L altera_mf -wlf wlfs_output_buffer_bank.wlf work.output_buffer_bank_tb
restart -force

catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 290
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Clock and reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/output_buffer_bank_tb/clk
add wave -radix binary sim:/output_buffer_bank_tb/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix unsigned sim:/output_buffer_bank_tb/rd_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/wr_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/data_in\(0\)
add wave -radix unsigned sim:/output_buffer_bank_tb/data_in\(1\)
add wave -radix unsigned sim:/output_buffer_bank_tb/data_in\(2\)
add wave -radix binary   sim:/output_buffer_bank_tb/wren
add wave -radix binary   sim:/output_buffer_bank_tb/rden
add wave -radix binary   sim:/output_buffer_bank_tb/read_group_sel

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/output_buffer_bank_tb/read_data\(0\)
add wave -radix unsigned sim:/output_buffer_bank_tb/read_data\(1\)
add wave -radix unsigned sim:/output_buffer_bank_tb/read_data\(2\)

# =======================
# Independent golden model
# =======================
add wave -divider {Golden_Model}
add wave -radix unsigned sim:/output_buffer_bank_tb/expected_read_data\(0\)
add wave -radix unsigned sim:/output_buffer_bank_tb/expected_read_data\(1\)
add wave -radix unsigned sim:/output_buffer_bank_tb/expected_read_data\(2\)

# =======================
# DUT internal BRAM outputs
# =======================
add wave -divider {DUT_Internal_Buffer_Data}
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(0\)
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(1\)
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(2\)
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(3\)
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(4\)
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/buffer_data\(5\)

# =======================
# output_buffers selected addresses
# =======================
add wave -divider {Output_Buffers_Internal}
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[0\]/bram_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[1\]/bram_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[2\]/bram_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[3\]/bram_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[4\]/bram_addr
add wave -radix unsigned sim:/output_buffer_bank_tb/dut/output_buffers_inst/gen_output_buffer\[5\]/bram_addr

# =======================
# Coverage / status
# =======================
add wave -divider {Coverage_And_Status}
add wave -radix binary   sim:/output_buffer_bank_tb/group0_path_covered
add wave -radix binary   sim:/output_buffer_bank_tb/group1_path_covered
add wave -radix binary   sim:/output_buffer_bank_tb/ping_pong_0_to_1_covered
add wave -radix binary   sim:/output_buffer_bank_tb/ping_pong_1_to_0_covered
add wave -radix binary   sim:/output_buffer_bank_tb/consecutive_read_covered
add wave -radix binary   sim:/output_buffer_bank_tb/async_reset_covered
add wave -radix unsigned sim:/output_buffer_bank_tb/errors
add wave -radix unsigned sim:/output_buffer_bank_tb/check_count

update
wave zoom full

run -all
