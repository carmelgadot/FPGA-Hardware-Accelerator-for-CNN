# ============================================================================
# wave_tb_output_buffer_fsm.do - waveform layout for tb_output_buffer_fsm.sv
# ----------------------------------------------------------------------------
# Ready-to-use compile + simulation + waveform configuration for
# tb_output_buffer_fsm.
#
# This testbench includes:
#   - Initial and runtime asynchronous reset checks
#   - Initial group-0 fill
#   - Parallel ping-pong write/read operation
#   - Read-finishes-first paths
#   - Write-finishes-first paths
#   - Simultaneous completion in both directions
#   - Independent abstract golden model
#   - Manual coverage of all defined FSM transitions
# ----------------------------------------------------------------------------
# What we will see
# - Clock_And_Reset : clk, resetb
# - TB_Stimulus     : write_done, read_done
# - DUT_Outputs     : en_write, en_read, write_group_sel, read_group_sel
# - DUT_State       : state, next_state
# - Golden_Model    : independent abstract write/read/group state
# - Scoreboard      : errors
# - TB_Coverage     : transition coverage and directed-event flags
# ----------------------------------------------------------------------------
# How to use (ModelSim)
#   do do_files/wave_tb_output_buffer_fsm.do
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
set DUT_PATH rtl/output_buffer_fsm.sv
set TB_PATH  tb/tb_output_buffer_fsm.sv

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
vsim -wlf wlfs_output_buffer_fsm.wlf work.tb_output_buffer_fsm
restart -force

# ============================================================================
# Wave window layout
# ============================================================================
configure wave -namecolwidth 300
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# ============================================================================
# FSM state names
# ============================================================================
radix define FSM_STATE {
    3'd0 "ST_FILL_GROUP0",
    3'd1 "ST_WRITE1_READ0",
    3'd2 "ST_WRITE1_ONLY",
    3'd3 "ST_WAIT_READ0",
    3'd4 "ST_WRITE0_READ1",
    3'd5 "ST_WRITE0_ONLY",
    3'd6 "ST_WAIT_READ1"
}

# =======================
# Clock / Reset
# =======================
add wave -divider {Clock_And_Reset}
add wave -radix binary sim:/tb_output_buffer_fsm/clk
add wave -radix binary sim:/tb_output_buffer_fsm/resetb

# =======================
# TB stimulus
# =======================
add wave -divider {TB_Stimulus}
add wave -radix binary sim:/tb_output_buffer_fsm/write_done
add wave -radix binary sim:/tb_output_buffer_fsm/read_done

# =======================
# DUT outputs
# =======================
add wave -divider {DUT_Outputs}
add wave -radix binary sim:/tb_output_buffer_fsm/en_write
add wave -radix binary sim:/tb_output_buffer_fsm/en_read
add wave -radix binary sim:/tb_output_buffer_fsm/write_group_sel
add wave -radix binary sim:/tb_output_buffer_fsm/read_group_sel

# =======================
# DUT state
# =======================
add wave -divider {DUT_State}
add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/state
add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/next_state
catch {add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/dut/state}
catch {add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/dut/next_state}

# =======================
# Independent golden model
# =======================
add wave -divider {Golden_Model}
add wave -radix binary sim:/tb_output_buffer_fsm/ref_initial_fill
add wave -radix binary sim:/tb_output_buffer_fsm/ref_write_active
add wave -radix binary sim:/tb_output_buffer_fsm/ref_read_active
add wave -radix binary sim:/tb_output_buffer_fsm/ref_write_group
add wave -radix binary sim:/tb_output_buffer_fsm/ref_read_group

# =======================
# Scoreboard
# =======================
add wave -divider {Scoreboard}
add wave -radix unsigned sim:/tb_output_buffer_fsm/errors

# =======================
# Manual TB coverage
# =======================
add wave -divider {TB_Coverage}
add wave -radix binary sim:/tb_output_buffer_fsm/async_reset_seen
add wave -radix binary sim:/tb_output_buffer_fsm/read_finishes_first_seen
add wave -radix binary sim:/tb_output_buffer_fsm/write_finishes_first_seen
add wave -radix binary sim:/tb_output_buffer_fsm/simultaneous_completion_seen

# transition_cov is an unpacked 7x7 array.
catch {add wave sim:/tb_output_buffer_fsm/transition_cov}

# Defined transition entries are also added individually for compatibility with
# ModelSim versions that do not automatically expand the unpacked array.
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[0][0]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[0][1]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[1][1]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[1][2]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[1][3]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[1][4]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[2][2]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[2][4]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[3][3]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[3][4]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[4][4]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[4][5]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[4][6]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[4][1]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[5][5]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[5][1]}}

catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[6][6]}}
catch {add wave -radix binary {sim:/tb_output_buffer_fsm/transition_cov[6][1]}}

# =======================
# Useful grouped view
# =======================
add wave -divider {Combined_View}
add wave -radix binary    sim:/tb_output_buffer_fsm/resetb
add wave -radix binary    sim:/tb_output_buffer_fsm/write_done
add wave -radix binary    sim:/tb_output_buffer_fsm/read_done
add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/state
add wave -radix FSM_STATE sim:/tb_output_buffer_fsm/next_state
add wave -radix binary    sim:/tb_output_buffer_fsm/en_write
add wave -radix binary    sim:/tb_output_buffer_fsm/en_read
add wave -radix binary    sim:/tb_output_buffer_fsm/write_group_sel
add wave -radix binary    sim:/tb_output_buffer_fsm/read_group_sel
add wave -radix unsigned  sim:/tb_output_buffer_fsm/errors

update
wave zoom full

# Always run to completion
run -all
