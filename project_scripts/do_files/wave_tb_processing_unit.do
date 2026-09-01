# ============================================================================
# wave_tb_processing_unit.do - waveform layout for tb_processing_unit.sv
# ----------------------------------------------------------------------------
# End-to-end simulation of:
#
#   input_subsystem -> conv_core -> output_subsystem
#
# The testbench golden model is a direct mathematical 3x3 convolution over a
# small padded image. It does not reproduce the RTL FSMs, PE hierarchy, counters,
# valid pipelines, circular-buffer mapping, or ping-pong implementation.
#
# How to use:
#   do do_files/wave_tb_processing_unit.do
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

set QUARTUS_SIM_LIB           "C:/Users/modelsim/modelsim_ase/altera/verilog/src"

set BRAM_PATH                 rtl/BRAM.v
set COUNTER_PATH              rtl/counter.sv

set WINDOW_FSM_PATH           rtl/window_manager_fsm.sv
set BUFFER_CONTROL_PATH       rtl/buffer_control.sv
set ROW_CONTROLLER_PATH       rtl/row_buffer_controller.sv
set INPUT_BUFFERS_PATH        rtl/input_buffers.sv
set ROW_MUX_PATH              rtl/row_buffer_mux.sv
set ROW_BANK_PATH             rtl/row_buffer_bank.sv
set INPUT_SUBSYSTEM_PATH      rtl/input_subsystem.sv

set PE_PATH                   rtl/PE.sv
set CONV_CORE_PATH            rtl/conv_core.sv

set OUTPUT_FSM_PATH           rtl/output_buffer_fsm.sv
set OUTPUT_CONTROLLER_PATH    rtl/output_buffer_controller.sv
set OUTPUT_BUFFERS_PATH       rtl/output_buffers.sv
set OUTPUT_MUX_PATH           rtl/output_buffer_mux.sv
set OUTPUT_BANK_PATH          rtl/output_buffer_bank.sv
set OUTPUT_SUBSYSTEM_PATH     rtl/output_subsystem.sv

set DUT_PATH                  rtl/processing_unit.sv
set TB_PATH                   tb/tb_processing_unit.sv

# ============================================================================
# Compile Intel/Altera simulation library for BRAM IP
# ============================================================================

if {![file exists altera_mf]} { vlib altera_mf }
vmap altera_mf altera_mf

vlog -work altera_mf "$QUARTUS_SIM_LIB/altera_mf.v"

# ============================================================================
# Compile complete processing-unit hierarchy and testbench
# ============================================================================

vlog -sv \
    $BRAM_PATH \
    $COUNTER_PATH \
    $WINDOW_FSM_PATH \
    $BUFFER_CONTROL_PATH \
    $ROW_CONTROLLER_PATH \
    $INPUT_BUFFERS_PATH \
    $ROW_MUX_PATH \
    $ROW_BANK_PATH \
    $INPUT_SUBSYSTEM_PATH \
    $PE_PATH \
    $CONV_CORE_PATH \
    $OUTPUT_FSM_PATH \
    $OUTPUT_CONTROLLER_PATH \
    $OUTPUT_BUFFERS_PATH \
    $OUTPUT_MUX_PATH \
    $OUTPUT_BANK_PATH \
    $OUTPUT_SUBSYSTEM_PATH \
    $DUT_PATH \
    $TB_PATH

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
vsim -L altera_mf -voptargs=+acc -wlf wlfs_processing_unit.wlf work.tb_processing_unit
restart -force

catch {delete wave *}

# ============================================================================
# Wave window layout
# ============================================================================

configure wave -namecolwidth 330
configure wave -valuecolwidth 160
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns

# =======================
# Clock / Reset / Input
# =======================

add wave -divider {Clock_Reset_Input}
add wave -radix binary   sim:/tb_processing_unit/clk
add wave -radix binary   sim:/tb_processing_unit/resetb
add wave -radix binary   sim:/tb_processing_unit/data_valid
add wave -radix binary   sim:/tb_processing_unit/frame_done
add wave -radix unsigned sim:/tb_processing_unit/data

# =======================
# Processing Unit Valid Path
# =======================

add wave -divider {Valid_Path}
add wave -radix binary sim:/tb_processing_unit/dut/input_rd_valid
add wave -radix binary sim:/tb_processing_unit/dut/input_read_valid_pipe
add wave -radix binary sim:/tb_processing_unit/dut/input_sample_valid
add wave -radix binary sim:/tb_processing_unit/dut/sample_valid_history
add wave -radix binary sim:/tb_processing_unit/dut/conv_launch_valid
add wave -radix binary sim:/tb_processing_unit/dut/conv_valid_pipe
add wave -radix binary sim:/tb_processing_unit/dut/conv_valid

# =======================
# Input Subsystem Pixels
# =======================

add wave -divider {Input_Subsystem_Pixels}
add wave -radix unsigned sim:/tb_processing_unit/dut/pixel_out\(0\)
add wave -radix unsigned sim:/tb_processing_unit/dut/pixel_out\(1\)
add wave -radix unsigned sim:/tb_processing_unit/dut/pixel_out\(2\)
add wave -radix unsigned sim:/tb_processing_unit/dut/pixel_out\(3\)
add wave -radix unsigned sim:/tb_processing_unit/dut/pixel_out\(4\)

# =======================
# Convolution Outputs
# =======================

add wave -divider {Conv_Core_Outputs}
add wave -radix unsigned sim:/tb_processing_unit/dut/conv_data\(0\)
add wave -radix unsigned sim:/tb_processing_unit/dut/conv_data\(1\)
add wave -radix unsigned sim:/tb_processing_unit/dut/conv_data\(2\)

# =======================
# External Outputs
# =======================

add wave -divider {External_Outputs}
add wave -radix binary   sim:/tb_processing_unit/out_valid
add wave -radix unsigned sim:/tb_processing_unit/read_data\(0\)
add wave -radix unsigned sim:/tb_processing_unit/read_data\(1\)
add wave -radix unsigned sim:/tb_processing_unit/read_data\(2\)

# =======================
# Input Controller Debug
# =======================

add wave -divider {Input_Controller_Debug}
add wave -radix unsigned sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/wr_addr
add wave -radix unsigned sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/rd_addr
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/bram_wr_en
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/bram_rd_en
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/row_padding
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/rd_valid
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/process_done
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/last_window
add wave -radix binary   sim:/tb_processing_unit/dut/u_input_subsystem/u_row_buffer_controller/frame_switch

# =======================
# Output Controller Debug
# =======================

add wave -divider {Output_Controller_Debug}
add wave -radix unsigned sim:/tb_processing_unit/dut/u_output_subsystem/wr_addr
add wave -radix unsigned sim:/tb_processing_unit/dut/u_output_subsystem/rd_addr
add wave -radix binary   sim:/tb_processing_unit/dut/u_output_subsystem/bram_wr_en
add wave -radix binary   sim:/tb_processing_unit/dut/u_output_subsystem/bram_rd_en
add wave -radix binary   sim:/tb_processing_unit/dut/u_output_subsystem/read_group_sel

# =======================
# Golden Model / Scoreboard
# =======================

add wave -divider {Golden_Model_Scoreboard}
add wave -radix unsigned sim:/tb_processing_unit/conv_valid_count
add wave -radix unsigned sim:/tb_processing_unit/received_count
add wave -radix unsigned sim:/tb_processing_unit/check_count
add wave -radix unsigned sim:/tb_processing_unit/error_count
add wave -radix unsigned sim:/tb_processing_unit/test4_received_count

# =======================
# Coverage
# =======================

add wave -divider {Coverage}
add wave -radix binary sim:/tb_processing_unit/async_reset_covered
add wave -radix binary sim:/tb_processing_unit/horizontal_padding_covered
add wave -radix binary sim:/tb_processing_unit/three_parallel_lanes_covered
add wave -radix binary sim:/tb_processing_unit/conv_valid_count_covered
add wave -radix binary sim:/tb_processing_unit/conv_data_alignment_covered
add wave -radix binary sim:/tb_processing_unit/output_order_covered
add wave -radix binary sim:/tb_processing_unit/no_early_output_covered
add wave -radix binary sim:/tb_processing_unit/complete_end_to_end_covered
add wave -radix binary sim:/tb_processing_unit/test4_active
add wave -radix binary sim:/tb_processing_unit/test4_padding_zero_covered
add wave -radix binary sim:/tb_processing_unit/test4_last_window_covered
add wave -radix binary sim:/tb_processing_unit/test4_frame_switch_covered
add wave -radix binary sim:/tb_processing_unit/test4_padding_cleared_covered
add wave -radix binary sim:/tb_processing_unit/test4_next_frame_covered
add wave -radix binary sim:/tb_processing_unit/test4_end_to_end_covered

# ============================================================================
# Run
# ============================================================================

run -all
wave zoom full
