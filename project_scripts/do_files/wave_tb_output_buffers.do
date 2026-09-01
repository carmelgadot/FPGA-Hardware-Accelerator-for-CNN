# ============================================================================
# wave_tb_output_buffers.do - waveform layout for tb_output_buffers.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_output_buffers.
# Includes Intel/Altera simulation library compilation for BRAM IP usage.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : rd_addr, wr_addr, data_in[0..2], wren, rden
# - DUT_Outputs     : q[0]..q[5]
# - Coverage        : functional coverage flags
# - DUT_Internal    : per-BRAM selected addresses
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_output_buffers.do
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
set DUT_PATH        rtl/output_buffers.sv
set TB_PATH         tb/tb_output_buffers.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================
if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf
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
vsim -L altera_mf -wlf wlfs_output_buffers.wlf work.tb_output_buffers
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
# Clock and reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/tb_output_buffers/clk
add wave -radix binary sim:/tb_output_buffers/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix unsigned sim:/tb_output_buffers/rd_addr
add wave -radix unsigned sim:/tb_output_buffers/wr_addr
add wave -radix unsigned sim:/tb_output_buffers/data_in\(0\)
add wave -radix unsigned sim:/tb_output_buffers/data_in\(1\)
add wave -radix unsigned sim:/tb_output_buffers/data_in\(2\)
add wave -radix binary   sim:/tb_output_buffers/wren
add wave -radix binary   sim:/tb_output_buffers/rden

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_output_buffers/q\(0\)
add wave -radix unsigned sim:/tb_output_buffers/q\(1\)
add wave -radix unsigned sim:/tb_output_buffers/q\(2\)
add wave -radix unsigned sim:/tb_output_buffers/q\(3\)
add wave -radix unsigned sim:/tb_output_buffers/q\(4\)
add wave -radix unsigned sim:/tb_output_buffers/q\(5\)

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal_BRAM_Addresses}
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[0\]/bram_addr
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[1\]/bram_addr
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[2\]/bram_addr
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[3\]/bram_addr
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[4\]/bram_addr
add wave -radix unsigned sim:/tb_output_buffers/dut/gen_output_buffer\[5\]/bram_addr

# =======================
# Coverage / scoreboard
# =======================
add wave -divider {Coverage_And_Scoreboard}
add wave -radix binary   sim:/tb_output_buffers/group0_write_covered
add wave -radix binary   sim:/tb_output_buffers/group1_write_covered
add wave -radix binary   sim:/tb_output_buffers/group0_read_covered
add wave -radix binary   sim:/tb_output_buffers/group1_read_covered
add wave -radix binary   sim:/tb_output_buffers/simultaneous_0_to_1_covered
add wave -radix binary   sim:/tb_output_buffers/simultaneous_1_to_0_covered
add wave -radix binary   sim:/tb_output_buffers/consecutive_read_covered
add wave -radix binary   sim:/tb_output_buffers/async_reset_covered
add wave -radix unsigned sim:/tb_output_buffers/error_count
add wave -radix unsigned sim:/tb_output_buffers/check_count

update
wave zoom full

run -all
