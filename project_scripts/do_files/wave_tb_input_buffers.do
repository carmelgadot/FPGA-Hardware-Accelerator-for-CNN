# ============================================================================
# wave_tb_input_buffers.do - waveform layout for tb_input_buffers.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for tb_input_buffers.
# Includes Intel/Altera simulation library compilation for BRAM IP usage.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : rd_addr, wr_addr, data, wren, rden
# - DUT_Outputs     : q[0]..q[NUM_BUFFERS-1]
# - Scoreboard      : error_count, check_count
# - DUT_Internal    : internal BRAM addresses and outputs
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_input_buffers.do
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
set QUARTUS_SIM_LIB "C:/Users/modelsim/modelsim_ase/altera/verilog/src"
set BRAM_PATH       rtl/BRAM.v
set DUT_PATH        rtl/input_buffers.sv
set TB_PATH         tb/tb_input_buffers.sv

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
vlog -sv $BRAM_PATH $DUT_PATH $TB_PATH

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
vsim -L altera_mf -wlf wlfs_input_buffers.wlf work.tb_input_buffers
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
add wave -radix binary   sim:/tb_input_buffers/clk
add wave -radix binary   sim:/tb_input_buffers/resetb

add wave -divider {TB_Stimulus}
add wave -radix unsigned sim:/tb_input_buffers/rd_addr
add wave -radix unsigned sim:/tb_input_buffers/wr_addr
add wave -radix unsigned      sim:/tb_input_buffers/data
add wave -radix binary   sim:/tb_input_buffers/wren
add wave -radix binary   sim:/tb_input_buffers/rden

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_input_buffers/q\(0\)
add wave -radix unsigned sim:/tb_input_buffers/q\(1\)
add wave -radix unsigned sim:/tb_input_buffers/q\(2\)
add wave -radix unsigned sim:/tb_input_buffers/q\(3\)
add wave -radix unsigned sim:/tb_input_buffers/q\(4\)
add wave -radix unsigned sim:/tb_input_buffers/q\(5\)
add wave -radix unsigned sim:/tb_input_buffers/q\(6\)
add wave -radix unsigned sim:/tb_input_buffers/q\(7\)

# =======================
# Scoreboard / TB counters
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_input_buffers/error_count
add wave -radix unsigned sim:/tb_input_buffers/check_count

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal}

# Per-buffer internal selected address
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[3\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[4\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[5\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[6\]/bram_addr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[7\]/bram_addr

# BRAM instance ports for a few representative buffers
add wave -divider {BRAM_Instance_0}
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/aclr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/address
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/clock
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/data
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/rden
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/wren
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[0\]/bram_inst/q

add wave -divider {BRAM_Instance_1}
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/aclr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/address
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/data
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/rden
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/wren
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[1\]/bram_inst/q

add wave -divider {BRAM_Instance_2}
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/aclr
add wave -radix unsigned sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/address
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/data
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/rden
add wave -radix binary   sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/wren
add wave -radix unsigned      sim:/tb_input_buffers/dut/gen_input_buffer\[2\]/bram_inst/q

# =======================
# Reference Model (optional)
# =======================
# Uncomment if you want to inspect scoreboard memory directly.
# Be aware this can be very heavy because DEPTH is large.
#
# add wave -divider {Reference_Model_Sample}
# add wave -radix unsigned sim:/tb_input_buffers/ref_mem\(0\)\(3\)
# add wave -radix unsigned sim:/tb_input_buffers/ref_mem\(5\)\(7\)
# add wave -radix unsigned sim:/tb_input_buffers/ref_mem\(1\)\(12\)
# add wave -radix unsigned sim:/tb_input_buffers/ref_mem\(2\)\(12\)
# add wave -radix unsigned sim:/tb_input_buffers/ref_mem\(3\)\(12\)

update
wave zoom full

# Always run to completion
run -all