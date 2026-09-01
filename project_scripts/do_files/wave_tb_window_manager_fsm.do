# ============================================================================
# wave_tb_window_manager_fsm.do - waveform layout for tb_window_manager_fsm.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_window_manager_fsm.
#
# This version matches the updated directed testbench:
#   - Initial asynchronous reset check
#   - Initial and next-frame row accumulation
#   - Updated WAIT_WRITE / WAIT_PROCESS behavior
#   - Normal window advance and frame switching
#   - Manual FSM transition coverage
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : row_write_done, process_done, frame_done,
#                     next_row_ready, write_blocked, last_window
# - DUT_Outputs     : en_write_row, en_process_window, advance_window, frame_switch
# - DUT_State       : state, next_state, rows_loaded, rows_done
# - Scoreboard      : errors
# - TB_Coverage     : transition coverage and directed-event flags
# - DUT_Internal    : internal state/counter control signals
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_window_manager_fsm.do
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
set DUT_PATH     rtl/window_manager_fsm.sv
set COUNTER_PATH rtl/counter.sv
set TB_PATH      tb/tb_window_manager_fsm.sv

# ============================================================================
# Compile DUT, counter and Testbench
# ============================================================================
vlog -sv $COUNTER_PATH $DUT_PATH $TB_PATH

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
vsim -wlf wlfs_window_manager_fsm.wlf work.tb_window_manager_fsm
restart -force

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 280
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# ============================================================================
# FSM state names
# ============================================================================
radix define FSM_STATE {
    3'd0 "ST_INIT_FILL",
    3'd1 "ST_RUN_BOTH",
    3'd2 "ST_WAIT_WRITE",
    3'd3 "ST_WAIT_PROCESS",
    3'd4 "ST_ADVANCE_WINDOW",
    3'd5 "ST_FRAME_SWITCH"
}

# =======================
# Clock / Reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary   sim:/tb_window_manager_fsm/clk
add wave -radix binary   sim:/tb_window_manager_fsm/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix binary   sim:/tb_window_manager_fsm/row_write_done
add wave -radix binary   sim:/tb_window_manager_fsm/process_done
add wave -radix binary   sim:/tb_window_manager_fsm/frame_done
add wave -radix binary   sim:/tb_window_manager_fsm/next_row_ready
add wave -radix binary   sim:/tb_window_manager_fsm/write_blocked
add wave -radix binary   sim:/tb_window_manager_fsm/last_window

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix binary   sim:/tb_window_manager_fsm/en_write_row
add wave -radix binary   sim:/tb_window_manager_fsm/en_process_window
add wave -radix binary   sim:/tb_window_manager_fsm/advance_window
add wave -radix binary   sim:/tb_window_manager_fsm/frame_switch

# =======================
# DUT state / counter
# =======================
add wave -divider {DUT_State}
add wave -radix FSM_STATE sim:/tb_window_manager_fsm/state
add wave -radix FSM_STATE sim:/tb_window_manager_fsm/next_state
add wave -radix unsigned sim:/tb_window_manager_fsm/rows_loaded
add wave -radix binary   sim:/tb_window_manager_fsm/rows_done

# =======================
# Scoreboard
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_window_manager_fsm/errors

# =======================
# Manual TB coverage
# =======================
add wave -divider {TB_Coverage}
add wave -radix binary sim:/tb_window_manager_fsm/async_reset_seen
add wave -radix binary sim:/tb_window_manager_fsm/frame_done_clear_seen
add wave -radix binary sim:/tb_window_manager_fsm/rows_accumulated_while_processing_seen

# transition_cov is an unpacked 6x6 array.
# Add the whole array when supported by the installed ModelSim/Questa version.
catch {add wave sim:/tb_window_manager_fsm/transition_cov}

# Individual defined transition entries are also added so they remain visible
# even on ModelSim versions that do not expand the whole array automatically.
# State index:
#   0 = INIT_FILL
#   1 = RUN_BOTH
#   2 = WAIT_WRITE
#   3 = WAIT_PROCESS
#   4 = ADVANCE_WINDOW
#   5 = FRAME_SWITCH
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[0][0]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[0][1]}}

catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[1][1]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[1][2]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[1][3]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[1][4]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[1][5]}}

catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[2][2]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[2][4]}}

catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[3][3]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[3][2]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[3][4]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[3][5]}}

catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[4][1]}}

catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[5][0]}}
catch {add wave -radix binary {sim:/tb_window_manager_fsm/transition_cov[5][1]}}

# =======================
# DUT internals
# =======================
add wave -divider {DUT_Internal}
catch {add wave -radix FSM_STATE sim:/tb_window_manager_fsm/dut/state}
catch {add wave -radix FSM_STATE sim:/tb_window_manager_fsm/dut/next_state}
catch {add wave -radix unsigned sim:/tb_window_manager_fsm/dut/rows_loaded}
catch {add wave -radix binary   sim:/tb_window_manager_fsm/dut/rows_loaded_en}

# Internal rows_loaded counter instance.
# frame_done is connected directly to the counter clr input.
catch {add wave -radix binary   sim:/tb_window_manager_fsm/dut/u_rows_loaded_counter/en}
catch {add wave -radix binary   sim:/tb_window_manager_fsm/dut/u_rows_loaded_counter/clr}
catch {add wave -radix unsigned sim:/tb_window_manager_fsm/dut/u_rows_loaded_counter/count}

# =======================
# Useful grouped view
# =======================
add wave -divider {Combined_View}
add wave -radix binary   sim:/tb_window_manager_fsm/resetb
add wave -radix binary   sim:/tb_window_manager_fsm/row_write_done
add wave -radix binary   sim:/tb_window_manager_fsm/process_done
add wave -radix FSM_STATE sim:/tb_window_manager_fsm/state
add wave -radix FSM_STATE sim:/tb_window_manager_fsm/next_state
add wave -radix unsigned sim:/tb_window_manager_fsm/rows_loaded
add wave -radix binary   sim:/tb_window_manager_fsm/rows_done
add wave -radix binary   sim:/tb_window_manager_fsm/rows_done
add wave -radix binary   sim:/tb_window_manager_fsm/en_write_row
add wave -radix binary   sim:/tb_window_manager_fsm/en_process_window
add wave -radix binary   sim:/tb_window_manager_fsm/advance_window
add wave -radix unsigned sim:/tb_window_manager_fsm/errors

update
wave zoom full

# Always run to completion
run -all
