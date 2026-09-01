# ============================================================================
# wave_tb_row_buffer_bank.do - waveform layout for row_buffer_bank_tb.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for row_buffer_bank_tb.
# Includes Intel/Altera simulation library compilation for BRAM IP usage.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : rd_addr, wr_addr, data, wren, rden, row_sel
# - DUT_Outputs     : pixel_out[0]..pixel_out[INIT_ROWS-1]
# - TB_Status       : errors
# - DUT_Internal    : physical BRAM outputs buffer_data[0]..buffer_data[NUM_BUFFERS-1]
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_row_buffer_bank.do
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
set INPUT_BUFFERS_PATH    rtl/input_buffers.sv
set ROW_BUFFER_MUX_PATH   rtl/row_buffer_mux.sv
set DUT_PATH              rtl/row_buffer_bank.sv
set TB_PATH               tb/row_buffer_bank_tb.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================
if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf

# Compile altera_mf library source
# BRAM IP uses altsyncram, which is defined in altera_mf.v
vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

# ============================================================================
# Compile DUT and Testbench
# ============================================================================
vlog -sv $BRAM_PATH $INPUT_BUFFERS_PATH $ROW_BUFFER_MUX_PATH $DUT_PATH $TB_PATH

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
vsim -L altera_mf -wlf wlfs_row_buffer_bank.wlf work.row_buffer_bank_tb
restart -force

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
add wave -radix binary   sim:/row_buffer_bank_tb/clk
add wave -radix binary   sim:/row_buffer_bank_tb/resetb

add wave -divider {TB_Stimulus}
add wave -radix unsigned sim:/row_buffer_bank_tb/rd_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/wr_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/data
add wave -radix binary   sim:/row_buffer_bank_tb/wren
add wave -radix binary   sim:/row_buffer_bank_tb/rden

# Logical-row to physical-buffer one-hot selection
add wave -radix binary sim:/row_buffer_bank_tb/row_sel\(0\)
add wave -radix binary sim:/row_buffer_bank_tb/row_sel\(1\)
add wave -radix binary sim:/row_buffer_bank_tb/row_sel\(2\)
add wave -radix binary sim:/row_buffer_bank_tb/row_sel\(3\)
add wave -radix binary sim:/row_buffer_bank_tb/row_sel\(4\)
add wave -radix binary sim:/row_buffer_bank_tb/row_padding

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/row_buffer_bank_tb/pixel_out\(0\)
add wave -radix unsigned sim:/row_buffer_bank_tb/pixel_out\(1\)
add wave -radix unsigned sim:/row_buffer_bank_tb/pixel_out\(2\)
add wave -radix unsigned sim:/row_buffer_bank_tb/pixel_out\(3\)
add wave -radix unsigned sim:/row_buffer_bank_tb/pixel_out\(4\)

# =======================
# TB status
# =======================
add wave -divider {TB_Status}
add wave -radix unsigned sim:/row_buffer_bank_tb/errors

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal}

# Physical BRAM outputs before logical-row selection
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(0\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(1\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(2\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(3\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(4\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(5\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(6\)
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/buffer_data\(7\)

# =======================
# input_buffers internals
# =======================
add wave -divider {Input_Buffers_Internal}

# Per-buffer internal selected address
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[3\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[4\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[5\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[6\]/bram_addr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[7\]/bram_addr

# BRAM instance ports for a few representative buffers
add wave -divider {BRAM_Instance_0}
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/aclr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/address
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/clock
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/data
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/rden
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/wren
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[0\]/bram_inst/q

add wave -divider {BRAM_Instance_1}
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/aclr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/address
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/data
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/rden
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/wren
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[1\]/bram_inst/q

add wave -divider {BRAM_Instance_2}
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/aclr
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/address
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/data
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/rden
add wave -radix binary   sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/wren
add wave -radix unsigned sim:/row_buffer_bank_tb/dut/input_buffers_inst/gen_input_buffer\[2\]/bram_inst/q

update
wave zoom full

# Always run to completion
run -all
