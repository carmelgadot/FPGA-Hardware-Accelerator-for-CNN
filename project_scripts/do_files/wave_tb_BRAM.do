# ============================================================================
# wave_tb_BRAM.do - waveform layout for tb_BRAM.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for tb_BRAM.
#
# BRAM.v is vendor-generated Intel/Altera IP. This simulation is intended to
# demonstrate the external behavior used by the project rather than verify the
# internal implementation of the IP.
#
# What we will see
# - Clock_And_Clear : clock, aclr
# - BRAM_Inputs     : address, data, rden, wren
# - BRAM_Output     : q
# - Coverage        : demonstration coverage flags, check_count, error_count
#
# How to use (ModelSim)
#   do do_files/wave_tb_BRAM.do
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

set QUARTUS_SIM_LIB "C:/Users/modelsim/modelsim_ase/altera/verilog/src"
set DUT_PATH        rtl/BRAM.v
set TB_PATH         tb/tb_BRAM.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================

if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf
vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

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
vsim -L altera_mf -voptargs=+acc -wlf wlfs_BRAM.wlf work.tb_BRAM
restart -force
catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================

configure wave -namecolwidth 290
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Clock and asynchronous clear
# =======================
add wave -divider {Clock_And_Clear}
add wave -radix binary sim:/tb_BRAM/clock
add wave -radix binary sim:/tb_BRAM/aclr

# =======================
# BRAM inputs
# =======================
add wave -divider {BRAM_Inputs}
add wave -radix unsigned sim:/tb_BRAM/address
add wave -radix hexadecimal sim:/tb_BRAM/data
add wave -radix binary sim:/tb_BRAM/rden
add wave -radix binary sim:/tb_BRAM/wren

# =======================
# BRAM output
# =======================
add wave -divider {BRAM_Output}
add wave -radix hexadecimal sim:/tb_BRAM/q

# =======================
# Coverage / status
# =======================
add wave -divider {Coverage_And_Status}
add wave -radix binary sim:/tb_BRAM/basic_write_read_covered
add wave -radix binary sim:/tb_BRAM/registered_read_covered
add wave -radix binary sim:/tb_BRAM/consecutive_reads_covered
add wave -radix binary sim:/tb_BRAM/read_during_write_covered
add wave -radix binary sim:/tb_BRAM/async_clear_covered
add wave -radix binary sim:/tb_BRAM/memory_retention_covered
add wave -radix unsigned sim:/tb_BRAM/check_count
add wave -radix unsigned sim:/tb_BRAM/error_count

update
run -all
wave zoom full
