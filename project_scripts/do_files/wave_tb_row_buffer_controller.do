# ============================================================================
# wave_tb_row_buffer_controller.do - waveform layout for tb_row_buffer_controller.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_row_buffer_controller.
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset       : clk, resetb
# - TB_Stimulus           : data_valid, frame_done
# - DUT_Outputs           : wr_addr, rd_addr, bram_wr_en, bram_rd_en,
#                           row_sel[0]..row_sel[INIT_ROWS-1], row_padding
# - FSM_And_Control       : state, rows_loaded, en_write_row,
#                           en_process_window, advance_window, frame_switch,
#                           next_row_ready, write_blocked, last_window,
#                           wr_valid, rd_valid, last_read_issued, read_pending,
#                           row_write_done, process_done
# - Buffer_Control        : fill_buffer_onehot, top_buffer_onehot,
#                           padding_mask, occupied_rows, active_read_mask
# - Scoreboard            : error_count, check_count
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_row_buffer_controller.do
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
set COUNTER_PATH        rtl/counter.sv
set FSM_PATH            rtl/window_manager_fsm.sv
set BUFFER_CONTROL_PATH rtl/buffer_control.sv
set DUT_PATH            rtl/row_buffer_controller.sv
set TB_PATH             tb/tb_row_buffer_controller.sv

# ============================================================================
# Compile DUT dependencies, DUT and Testbench
# ============================================================================
vlog -sv $COUNTER_PATH $FSM_PATH $BUFFER_CONTROL_PATH $DUT_PATH $TB_PATH

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
vsim -wlf wlfs_row_buffer_controller.wlf work.tb_row_buffer_controller
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
add wave -radix binary sim:/tb_row_buffer_controller/clk
add wave -radix binary sim:/tb_row_buffer_controller/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix binary sim:/tb_row_buffer_controller/data_valid
add wave -radix binary sim:/tb_row_buffer_controller/frame_done

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix unsigned sim:/tb_row_buffer_controller/wr_addr
add wave -radix unsigned sim:/tb_row_buffer_controller/rd_addr
add wave -radix binary sim:/tb_row_buffer_controller/bram_wr_en
add wave -radix binary sim:/tb_row_buffer_controller/bram_rd_en

add wave -divider {Row_Selectors}
add wave -radix binary sim:/tb_row_buffer_controller/row_sel\(0\)
add wave -radix binary sim:/tb_row_buffer_controller/row_sel\(1\)
add wave -radix binary sim:/tb_row_buffer_controller/row_sel\(2\)
add wave -radix binary sim:/tb_row_buffer_controller/row_sel\(3\)
add wave -radix binary sim:/tb_row_buffer_controller/row_sel\(4\)
add wave -radix binary sim:/tb_row_buffer_controller/row_padding

# =======================
# FSM and controller integration
# =======================
add wave -divider {FSM_And_Control}
add wave -radix unsigned sim:/tb_row_buffer_controller/state
add wave -radix unsigned sim:/tb_row_buffer_controller/rows_loaded

add wave -radix binary sim:/tb_row_buffer_controller/en_write_row
add wave -radix binary sim:/tb_row_buffer_controller/en_process_window
add wave -radix binary sim:/tb_row_buffer_controller/advance_window
add wave -radix binary sim:/tb_row_buffer_controller/frame_switch

add wave -radix binary sim:/tb_row_buffer_controller/next_row_ready
add wave -radix binary sim:/tb_row_buffer_controller/write_blocked
add wave -radix binary sim:/tb_row_buffer_controller/last_window

add wave -radix binary sim:/tb_row_buffer_controller/wr_valid
add wave -radix binary sim:/tb_row_buffer_controller/rd_valid
add wave -radix binary sim:/tb_row_buffer_controller/last_read_issued
add wave -radix binary sim:/tb_row_buffer_controller/read_pending
add wave -radix binary sim:/tb_row_buffer_controller/row_write_done
add wave -radix binary sim:/tb_row_buffer_controller/process_done

# =======================
# Buffer-control internals
# =======================
add wave -divider {Buffer_Control}
add wave -radix binary sim:/tb_row_buffer_controller/fill_buffer_onehot
add wave -radix binary sim:/tb_row_buffer_controller/top_buffer_onehot
add wave -radix binary sim:/tb_row_buffer_controller/padding_mask
add wave -radix unsigned sim:/tb_row_buffer_controller/occupied_rows
add wave -radix binary sim:/tb_row_buffer_controller/active_read_mask

# =======================
# Scoreboard / TB counters
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_row_buffer_controller/error_count
add wave -radix unsigned sim:/tb_row_buffer_controller/check_count

update
wave zoom full

# Always run to completion
run -all
