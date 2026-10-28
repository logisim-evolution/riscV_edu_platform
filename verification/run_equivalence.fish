#!/usr/bin/env fish

# Script to run equivalence checks using formally using the SAT solver of yosys.

set script_dir (dirname (status filename))
set repo_root (realpath "$script_dir/..")
set build_dir "$repo_root/verification/build"
set results_file "$build_dir/results.txt"

set check_mode $argv[1]

if test -z "$check_mode" # No argument passed? default it is then
    set check_mode default
end

if not contains -- $check_mode default full debug hazard4edu
    printf 'Usage: %s [default|debug|hazard4edu|full]\n' (status filename) >&2
    exit 2
end

source /opt/oss-cad-suite/environment.fish

rm -rf $build_dir
mkdir -p $build_dir
printf 'module,status\n' > $results_file

# Compares two implementations of a design, the Verilog (gold) and the VHDL (gate).
# Parameters:
#   name                Name of the design to check. Used only for folder and filename generation.
#   top                 Name of the top level entity to compare
#   vhdl_files          VHDL files. If the DUT relies on other entities, add them before the DUT path
#   verilog_files       Verilog files. If the DUT relies on other  entities, add them before the DUT path
#   reset_constraints   Definitions for the reset pin. E.g. at step one, assert reset_n, then in step 2, deassert it (-set-at 1 rst_n 0 -set_at 2 rst_n 1)
#   verilog_include_dir Directory to search for Verilog include files.
#   blackbox_file       Some entities might rely on vendor-specific blackboxes to be instantiated. Here a dummy blackbox entity can be provided.
#   sat_cycles          Override the default 12 cycles for the -seq parameter. See https://yosyshq.readthedocs.io/projects/yosys/en/0.47/cmd/sat.html
#   generic_values      Optional space-separated NAME=value overrides for both VHDL generics and Verilog parameters.
#                       Vector values must not contain spaces. For example:
#                       NUMBER_OF_IRQs=2 IRQ_PRIORITY_BITS=1 IRQ_INPUT_BYPASS=(true,false)
function check_assert_reset_pair
    # Read in the received parameters
    set -l name $argv[1]
    set -l top $argv[2]
    set -l vhdl_files $argv[3]
    set -l verilog_files $argv[4]
    set -l reset_constraints $argv[5]
    set -l verilog_include_dir $argv[6]
    set -l blackbox_file $argv[7]
    set -l sat_cycles $argv[8]
    set -l generic_values $argv[9]
    
    set -l work_dir "$build_dir/$name/ghdl-work"                # Set the work folder for GHDL
    set -l silver_file "$build_dir/$name/$top.v"                # file name for the transpiled VHDL-to-Verilog
    set -l log_file "$build_dir/$name/$top.log"
    set -l vhdl_args (string split ' ' -- $vhdl_files)          # Split the VHDL files to a proper Fish array
    set -l verilog_args (string split ' ' -- $verilog_files)    # ^ but for Verilog
    set -l vhdl_generic_args
    set -l verilog_chparam ''
    set -l vhdl_bypass_value ''

    for generic_value in (string split ' ' -- $generic_values)
        set -a vhdl_generic_args "-g$generic_value"
        set -l parameter (string split '=' -- $generic_value)
        set -l generic_name $parameter[1]
        set -l generic_value_text $parameter[2]
        set -l vhdl_parameter $generic_name
        set -l verilog_parameter $generic_name
        set -l verilog_value $generic_value_text
        # The VHDL IRQ controller uses descriptive generic names while the
        # reference Verilog uses the original Hazard3 parameter names.
        if test "$generic_name" = NUMBER_OF_IRQs
            set verilog_parameter NUM_IRQS
        else if test "$generic_name" = IRQ_INPUT_BYPASS
            set vhdl_parameter IRQ_INPUTREG_BYPASS
        else if test "$generic_name" = IRQ_INPUTREG_BYPASS
            set verilog_parameter IRQ_INPUT_BYPASS
        end
        if test "$vhdl_parameter" = IRQ_INPUTREG_BYPASS
            set vhdl_bypass_value $generic_value_text
            set -l bypass_values (string split ',' -- (string trim -c '()' -- $generic_value_text))
            set -l bypass_bits
            for bypass_value in $bypass_values
                if test "$bypass_value" = true
                    set -a bypass_bits 1
                else if test "$bypass_value" = false
                    set -a bypass_bits 0
                else
                    printf 'Unsupported IRQ bypass value: %s\n' "$bypass_value" >&2
                    return 1
                end
            end
            set bypass_bit_string (string join '' -- $bypass_bits)
            set verilog_value (string join '' -- (count $bypass_bits) "'b" $bypass_bit_string)
            set verilog_chparam "$verilog_chparam chparam -set $verilog_parameter $verilog_value gold;"
            continue
        else if test "$generic_name" = RESET_VECTOR
            # Passed as a plain bit string, which GHDL accepts for vector generics
            set verilog_value "32'b$generic_value_text"
        else if test "$verilog_value" = true
            set verilog_value 1
        else if test "$verilog_value" = false
            set verilog_value 0
        end
        set verilog_chparam "$verilog_chparam chparam -set $verilog_parameter $verilog_value gold;"
    end
    
    set -l verilog_include ''
    if test -n "$verilog_include_dir"
        set verilog_include "-I$verilog_include_dir"
    end

    # Create folder if it doesn't exist already
    mkdir -p "$build_dir/$name" $work_dir
    printf '\n=== %s (reset-constrained assertions) ===\n' $name | tee $log_file

    # GHDL does not accept aggregate values for boolean_vector generics via
    # -g. Apply the vector to a temporary copy of the top-level source instead.
    if test -n "$vhdl_bypass_value"
        set -l vhdl_top_source $vhdl_args[-1]
        set -l vhdl_override_file "$work_dir/$top.generic.vhdl"
        sed "s/:= (others => FALSE)/:= $vhdl_bypass_value/" "$vhdl_top_source" > "$vhdl_override_file"
        set vhdl_args[-1] "$vhdl_override_file"
        set vhdl_generic_args (string match -v -- '-gIRQ_INPUTREG_BYPASS=*' $vhdl_generic_args)
        set vhdl_generic_args (string match -v -- '-gIRQ_INPUT_BYPASS=*' $vhdl_generic_args)
    end

    # Synthesize the VHDL entity to Verilog, log the output, print if a fail occurred
    if not ghdl --synth --std=08 --out=verilog --workdir=$work_dir $vhdl_generic_args $vhdl_args -e $top >$silver_file 2>>$log_file
        printf '❌ %s,ghdl-synth-failed\n' $name >> $results_file
        printf '❌ GHDL synthesis failed: %s\n' $name | tee -a $log_file
        return 1
    end

    # Default to 12 clock cycles if no 7th argument is provided (or if it is empty)
    if test -z "$sat_cycles"
        set sat_cycles 12
    end

    # Dealing with a blackbox entity requires extra care, but is only passed over to yosys if such a parameter has been provided
    set -l blackbox_command ''
    set -l sat_options ''
    if test -n "$blackbox_file"
        set blackbox_command "read_verilog -formal $blackbox_file;" # Read in the verilog blackbox, enable formal verification support
        set sat_options '-ignore-unknown-cells'                     # Tells Yosys SAT solver to not fail if it encounters cells without definitions (aka blackboxes)
    end

    # Here is the meat of the bone!
    # While the comments are within the double quotes, yosys reads in each line
    # ignores everything after the # symbol, executing the commands in order.
    # The ; symbol serves a similar purpose, to execute the previous instruction before the next.
    set -l yosys_script "
        $blackbox_command                                   # Load in the blackbox if any was set
        read_verilog -formal $verilog_include $verilog_args # Read the reference Verilog files
        rename $top gold                                    # Rename the reference top module to 'gold'
        $verilog_chparam                                    # Override the reference parameters
        hierarchy -top gold                                 # Elaborate and flatten gold
        proc; flatten; memory; async2sync
        read_verilog -formal $silver_file                   # Read in the GHDL synthesized netlist
        rename $top silver                                  # Rename netlist top module to 'silver'
        proc; flatten silver; memory; async2sync            # Flatten silver without deleting gold        proc; memory; async2sync                            # Standard synthesis pre-processing passes
        equiv_make -make_assert gold silver equiv           # Create equivalence checking module
        prep -top equiv                                     # Prepare the new 'equiv' module as top
        async2sync; opt                                     # Optimize and map clocks to logic
        sat $sat_options -seq $sat_cycles -verify -prove-asserts -set-init-zero -show-inputs -show-outputs \
        $reset_constraints   # Run SAT solver with optional reset constraints
    "

    # Execute yosys with the above script, log the output.
    if not yosys -p "$yosys_script" >>$log_file 2>&1
        # If something fails, print it and return early non-zero
        printf '❌ %s,equivalence-failed\n' $name >> $results_file
        printf '❌ Reset-constrained equivalence failed: %s\n' $name | tee -a $log_file
        return 1
    end

    # Everything went well, return zero
    printf '✅ %s,proven\n' $name >> $results_file
    printf '✅ Reset-constrained proof: %s\n' $name | tee -a $log_file
    return 0
end

set failed 0


# =============================================================================
# |                        DEBUG EQUIVALENCE CHECKS                           |
# =============================================================================

if test "$check_mode" = debug -o "$check_mode" = full
    check_assert_reset_pair hazard3_sync_1bit hazard3_sync_1bit \
        "$repo_root/hdl/modules/debug/vhdl/hazard3_sync_1bit.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/hazard3_sync_1bit.v" \
        "-set-at 1 rst 1 -set-at 2 rst 0"
    or set failed 1

    check_assert_reset_pair hazard3_reset_sync hazard3_reset_sync \
        "$repo_root/hdl/modules/debug/vhdl/hazard3_reset_sync.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/hazard3_reset_sync.v" \
        "-set-at 1 rst_in 1 -set-at 2 rst_in 0"
    or set failed 1

    check_assert_reset_pair hazard3_apb_async_bridge hazard3_apb_async_bridge \
        "$repo_root/hdl/modules/debug/vhdl/hazard3_sync_1bit.vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_apb_async_bridge.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/hazard3_sync_1bit.v $repo_root/hdl/modules/debug/verilog/hazard3_apb_async_bridge.v" \
        "-set-at 1 rst_src 1 -set-at 1 rst_dst 1 -set-at 2 rst_src 0 -set-at 2 rst_dst 0"
    or set failed 1

    check_assert_reset_pair hazard3_dm hazard3_dm \
        "$repo_root/hdl/modules/debug/vhdl/hazard3_dm.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/hazard3_dm.v" \
        "-set-at 1 RST_I 1 -set-at 2 RST_I 0" \
        '' '' \
        "8"
    or set failed 1

    # The JTAG debug modules have the following files as common dependency.
    set -l dtm_vhdl "$repo_root/hdl/modules/debug/vhdl/hazard3_sync_1bit.vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_apb_async_bridge.vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_jtag_dtm_core.vhdl"
    set -l dtm_verilog "$repo_root/hdl/modules/debug/verilog/hazard3_sync_1bit.v $repo_root/hdl/modules/debug/verilog/hazard3_apb_async_bridge.v $repo_root/hdl/modules/debug/verilog/hazard3_jtag_dtm_core.v"

    check_assert_reset_pair hazard3_jtag_dtm_core hazard3_jtag_dtm_core "$dtm_vhdl" "$dtm_verilog" \
        "-set-at 1 trst_n 0 -set-at 1 rst_dmi 1 -set-at 2 trst_n 1 -set-at 2 rst_dmi 0"
    or set failed 1

    check_assert_reset_pair hazard3_ecp5_jtag_dtm hazard3_ecp5_jtag_dtm \
        "$dtm_vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_ecp5_jtag_dtm.vhdl" \
        "$dtm_verilog $repo_root/hdl/modules/debug/verilog/hazard3_ecp5_jtag_dtm.v" \
        "-set-at 1 rst_dmi 1 -set-at 2 rst_dmi 0" \
        '' \
        "$repo_root/verification/ecp5_jtagg_blackbox.v"
    or set failed 1

    set -a dtm_vhdl "$repo_root/hdl/modules/debug/vhdl/hazard3_reset_sync.vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_ecp5_jtag_dtm.vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_dm.vhdl"
    set -a dtm_verilog "$repo_root/hdl/modules/debug/verilog/hazard3_reset_sync.v $repo_root/hdl/modules/debug/verilog/hazard3_ecp5_jtag_dtm.v $repo_root/hdl/modules/debug/verilog/hazard3_dm.v"

    check_assert_reset_pair debugTop debugTop \
        "$dtm_vhdl $repo_root/hdl/modules/debug/vhdl/debugTop.vhdl" \
        "$dtm_verilog $repo_root/hdl/modules/debug/verilog/debugTop.v" \
        "-set-at 1 RST_I 1 -set-at 2 RST_I 0" \
        '' \
        "$repo_root/verification/ecp5_jtagg_blackbox.v"
    or set failed 1
end

# =============================================================================
# |                     HAZARD4EDU EQUIVALENCE CHECKS                         |
# =============================================================================

if test "$check_mode" = hazard4edu -o "$check_mode" = full
    set -l hazard_vhdl "$repo_root/hdl/modules/hazard4edu/vhdl"
    set -l hazard_verilog "$repo_root/hdl/modules/hazard4edu/verilog"

    set -l hazard_alu_vhdl "$hazard_vhdl/hazard3_pkg.vhdl"
    set -l hazard_alu_verilog ''

    check_assert_reset_pair hazard3_shift_barrel hazard3_shift_barrel \
        "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_shift_barrel.vhdl" \
        "$hazard_alu_verilog $hazard_verilog/arith/hazard3_shift_barrel.v" \
        '' \
        "$hazard_verilog"
    or set failed 1

    check_assert_reset_pair hazard3_branchcmp hazard3_branchcmp \
        "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_branchcmp.vhdl" \
        "$hazard_alu_verilog $hazard_verilog/arith/hazard3_branchcmp.v" \
        '' \
        "$hazard_verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_encode hazard3_onehot_encode \
        "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_onehot_encode.vhdl" \
        "$hazard_alu_verilog $hazard_verilog/arith/hazard3_onehot_encode.v" \
        '' \
        "$hazard_verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_priority hazard3_onehot_priority \
        "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_onehot_priority.vhdl" \
        "$hazard_alu_verilog $hazard_verilog/arith/hazard3_onehot_priority.v" \
        '' \
        "$hazard_verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_priority_dynamic hazard3_onehot_priority_dynamic \
        "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_onehot_priority.vhdl $hazard_vhdl/arith/hazard3_onehot_priority_dynamic.vhdl" \
        "$hazard_alu_verilog $hazard_verilog/arith/hazard3_onehot_priority.v $hazard_verilog/arith/hazard3_onehot_priority_dynamic.v" \
        '' \
        "$hazard_verilog"
    or set failed 1

    set -a hazard_alu_vhdl "$hazard_vhdl/arith/hazard3_shift_barrel.vhdl"
    set -a hazard_alu_verilog "$hazard_verilog/arith/hazard3_shift_barrel.v"

    for configuration in \
        'EXTENSION_A=false' \
        'EXTENSION_A=true' 
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_alu_$configuration_name" hazard3_alu \
            "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_alu.vhdl" \
            "$hazard_alu_verilog $hazard_verilog/arith/hazard3_alu.v" \
            '' \
            "$hazard_verilog" \
            '' '' \
            "$configuration"
        or set failed 1
    end

    # Check every legal combination of the multiplier generics. Invalid combinations
    # are rejected by both implementations during elaboration.

    for configuration in \
        'MULH_FAST=false MUL_FAST=false' \
        'MULH_FAST=false MUL_FAST=true' \
        'MULH_FAST=true MUL_FAST=false' \
        'MULH_FAST=true MUL_FAST=true'
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_muldiv_seq_$configuration_name" hazard3_muldiv_seq \
            "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_muldiv_seq.vhdl" \
            "$hazard_alu_verilog $hazard_verilog/arith/hazard3_muldiv_seq.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' '' \
            "$configuration"
        or set failed 1
    end 

    for configuration in \
        'MULH_FAST=false MUL_FAST=false MUL_FASTER=false RISCV_FORMAL_ALTOPS=false' \
        'MULH_FAST=false MUL_FAST=true MUL_FASTER=false RISCV_FORMAL_ALTOPS=false' \
        'MULH_FAST=false MUL_FAST=true MUL_FASTER=true RISCV_FORMAL_ALTOPS=false' \
        'MULH_FAST=true MUL_FAST=true MUL_FASTER=false RISCV_FORMAL_ALTOPS=true' \
        'MULH_FAST=true MUL_FAST=true MUL_FASTER=true RISCV_FORMAL_ALTOPS=true'
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_mul_fast_$configuration_name" hazard3_mul_fast \
            "$hazard_alu_vhdl $hazard_vhdl/arith/hazard3_mul_fast.vhdl" \
            "$hazard_alu_verilog $hazard_verilog/arith/hazard3_mul_fast.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 2 \
            "$configuration"
        or set failed 1
    end

    set -a hazard_vhdl_dep "$hazard_vhdl/hazard3_pkg.vhdl"
    set -a hazard_verilog_dep ""

    for configuration in \
        'DEBUG_SUPPORT=false BREAKPOINT_TRIGGERS=0 U_MODE=false EXTENSION_C=false' \
        'DEBUG_SUPPORT=true BREAKPOINT_TRIGGERS=2 U_MODE=false EXTENSION_C=false' \
        'DEBUG_SUPPORT=true BREAKPOINT_TRIGGERS=2 U_MODE=true EXTENSION_C=false' \
        'DEBUG_SUPPORT=true BREAKPOINT_TRIGGERS=2 U_MODE=false EXTENSION_C=true' \
        'DEBUG_SUPPORT=true BREAKPOINT_TRIGGERS=2 U_MODE=true EXTENSION_C=true'
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_triggers_$configuration_name" hazard3_triggers \
            "$hazard_vhdl_dep $hazard_vhdl/hazard3_triggers.vhdl" \
            "$hazard_verilog_dep $hazard_verilog/hazard3_triggers.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 6 \
            "$configuration"
        or set failed 1
    end

    for configuration in \
        'EXTENSION_C=false EXTENSION_M=false' \
        'EXTENSION_C=false EXTENSION_M=true' \
        'EXTENSION_C=true EXTENSION_M=false' \
        'EXTENSION_C=true EXTENSION_M=true'
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_instr_decompress_$configuration_name" hazard3_instr_decompress \
            "$hazard_vhdl_dep $hazard_vhdl/hazard3_instr_decompress.vhdl" \
            "$hazard_verilog_dep $hazard_verilog/hazard3_instr_decompress.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 6 \
            "$configuration"
        or set failed 1
    end

    # Configurations:
    # 1. RV32I without A, C, M (every "else invalid" branch, C forcing d_instr[1:0]); nonzero RESET_VECTOR
    # 2. RV32EC without A and M, debug + branch predictor
    # 3. RV32IAM without C, branch predictor
    set -l decode_configurations
    for csr_m_mandatory in false true
        for csr_m_trap in false true
            for csr_counter in false true
                for u_mode in false true
                    set -a decode_configurations \
                        "CSR_M_MANDATORY=$csr_m_mandatory CSR_M_TRAP=$csr_m_trap CSR_COUNTER=$csr_counter U_MODE=$u_mode"
                end
            end
        end
    end
    set -a decode_configurations \
        'EXTENSION_A=false EXTENSION_C=false EXTENSION_E=false EXTENSION_M=false CSR_M_MANDATORY=true CSR_M_TRAP=true CSR_COUNTER=false U_MODE=false DEBUG_SUPPORT=false BRANCH_PREDICTOR=false RESET_VECTOR=00100000000000000000001000000000' \
        'EXTENSION_A=false EXTENSION_C=true EXTENSION_E=true EXTENSION_M=false CSR_M_MANDATORY=true CSR_M_TRAP=true CSR_COUNTER=false U_MODE=false DEBUG_SUPPORT=true BRANCH_PREDICTOR=true' \
        'EXTENSION_A=true EXTENSION_C=false EXTENSION_E=false EXTENSION_M=true CSR_M_MANDATORY=true CSR_M_TRAP=true CSR_COUNTER=false U_MODE=false DEBUG_SUPPORT=false BRANCH_PREDICTOR=true'

    for configuration in $decode_configurations
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0' | string replace -a '=' '_')
        check_assert_reset_pair "hazard3_decode_$configuration_name" hazard3_decode \
            "$hazard_vhdl_dep $hazard_vhdl/hazard3_decode.vhdl" \
            "$hazard_verilog_dep $hazard_verilog/hazard3_decode.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' '' \
            "$configuration"
        or set failed 1
    end

    set -l hazard_vhdl_irq_ctrl_dep "$hazard_vhdl/hazard3_pkg.vhdl $hazard_vhdl/arith/hazard3_onehot_priority.vhdl $hazard_vhdl/arith/hazard3_onehot_priority_dynamic.vhdl $hazard_vhdl/arith/hazard3_onehot_encode.vhdl"
    set -l hazard_verilog_irq_ctrl_dep "$hazard_verilog/arith/hazard3_onehot_priority.v $hazard_verilog/arith/hazard3_onehot_priority_dynamic.v $hazard_verilog/arith/hazard3_onehot_encode.v"

    
    check_assert_reset_pair hazard3_irq_ctrl hazard3_irq_ctrl \
        "$hazard_vhdl_irq_ctrl_dep $hazard_vhdl/hazard3_irq_ctrl.vhdl" \
        "$hazard_verilog_irq_ctrl_dep $hazard_verilog/hazard3_irq_ctrl.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog"
    or set failed 1

    # Exercise the parameterized IRQ controller as well as the default
    # configuration. The non-power-of-two case checks IRQ index padding. Manual semi-random
    # IRQ bypass to check the correct bypass behaviour per IRQ line.
    check_assert_reset_pair hazard3_irq_ctrl_irq2_prio1_bypass10 hazard3_irq_ctrl \
        "$hazard_vhdl_irq_ctrl_dep $hazard_vhdl/hazard3_irq_ctrl.vhdl" \
        "$hazard_verilog_irq_ctrl_dep $hazard_verilog/hazard3_irq_ctrl.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog" '' '' 'NUMBER_OF_IRQs=2 IRQ_PRIORITY_BITS=1 IRQ_INPUT_BYPASS=(true,false)'
    or set failed 1

    check_assert_reset_pair hazard3_irq_ctrl_irq3_prio2_bypass010 hazard3_irq_ctrl \
        "$hazard_vhdl_irq_ctrl_dep $hazard_vhdl/hazard3_irq_ctrl.vhdl" \
        "$hazard_verilog_irq_ctrl_dep $hazard_verilog/hazard3_irq_ctrl.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog" '' '' 'NUMBER_OF_IRQs=3 IRQ_PRIORITY_BITS=2 IRQ_INPUT_BYPASS=(false,true,false)'
    or set failed 1

    check_assert_reset_pair hazard3_irq_ctrl_irq4_prio4_bypass1010 hazard3_irq_ctrl \
        "$hazard_vhdl_irq_ctrl_dep $hazard_vhdl/hazard3_irq_ctrl.vhdl" \
        "$hazard_verilog_irq_ctrl_dep $hazard_verilog/hazard3_irq_ctrl.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog" '' '' 'NUMBER_OF_IRQs=4 IRQ_PRIORITY_BITS=4 IRQ_INPUT_BYPASS=(true,false,true,false)'
    or set failed 1

    for configuration in \
        'EXTENSION_E=false RESET_REGFILE=false' \
        'EXTENSION_E=false RESET_REGFILE=true' \
        'EXTENSION_E=true RESET_REGFILE=false' \
        'EXTENSION_E=true RESET_REGFILE=true'
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_regfile_1w2r_$configuration_name" hazard3_regfile_1w2r \
            "$hazard_vhdl_dep $hazard_vhdl/hazard3_regfile_1w2r.vhdl" \
            "$hazard_verilog_dep $hazard_verilog/hazard3_regfile_1w2r.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 5 \
            "$configuration"
        or set failed 1
    end

        # Include dependencies required when EXTENSION_XH3IRQ=true instantiates hazard3_irq_ctrl
    set -l hazard_csr_vhdl_dep \
        "$hazard_vhdl/hazard3_pkg.vhdl" \
        "$hazard_vhdl/arith/hazard3_onehot_priority.vhdl" \
        "$hazard_vhdl/arith/hazard3_onehot_priority_dynamic.vhdl" \
        "$hazard_vhdl/arith/hazard3_onehot_encode.vhdl" \
        "$hazard_vhdl/hazard3_irq_ctrl.vhdl"

    set -l hazard_csr_verilog_dep \
        "$hazard_verilog/arith/hazard3_onehot_priority.v" \
        "$hazard_verilog/arith/hazard3_onehot_priority_dynamic.v" \
        "$hazard_verilog/arith/hazard3_onehot_encode.v" \
        "$hazard_verilog/hazard3_irq_ctrl.v"

    # 1. Default baseline (all features disabled / default values)
    check_assert_reset_pair hazard3_csr_default hazard3_csr \
        "$hazard_csr_vhdl_dep $hazard_vhdl/hazard3_csr.vhdl" \
        "$hazard_csr_verilog_dep $hazard_verilog/hazard3_csr.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog"
    or set failed 1

    # 2. Sensible orthogonal configurations covering all RTL branches & interactions:
    # - Config 1: Mandatory CSRs only + RV32E + C + M (with Zkt=0 via MUL_FAST=0, MULH_FAST=0)
    # - Config 2: Trap CSRs only + Non-MISA extensions + Xh3irq generate block active
    # - Config 3: Mandatory + Trap (enables MSCRATCH) + Counters + U_MODE (enables MCOUNTEREN & U-RO CSRs) + PMP (standard)
    # - Config 4: Debug + Trap + U_MODE + C (tests C_SHIFT=1 in DPC & MEPC_MASK) + PMP with Xh3pmpm
    # - Config 5: Maximal feature set enabled (tests Zkt=1 via MUL_FAST=1, MULH_FAST=1, plus all concurrent paths)
    for configuration in \
        'CSR_M_MANDATORY=true CSR_M_TRAP=false EXTENSION_C=true EXTENSION_E=true EXTENSION_M=true MUL_FAST=false MULH_FAST=false' \
        'CSR_M_MANDATORY=false CSR_M_TRAP=true EXTENSION_XH3IRQ=true EXTENSION_A=true' \
        'CSR_M_MANDATORY=true CSR_M_TRAP=true CSR_COUNTER=true U_MODE=true PMP_REGIONS=1 EXTENSION_XH3PMPM=false' \
        'CSR_M_MANDATORY=true CSR_M_TRAP=true U_MODE=true DEBUG_SUPPORT=true EXTENSION_C=true PMP_REGIONS=2 EXTENSION_XH3PMPM=true' \
        'CSR_M_MANDATORY=true CSR_M_TRAP=true CSR_COUNTER=true PMP_REGIONS=2 EXTENSION_A=true EXTENSION_C=true EXTENSION_E=false EXTENSION_M=true MUL_FAST=true MULH_FAST=true EXTENSION_XH3PMPM=true EXTENSION_XH3IRQ=true U_MODE=true DEBUG_SUPPORT=true'
        
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0' | string replace -a '=' '_')
        check_assert_reset_pair "hazard3_csr_$configuration_name" hazard3_csr \
            "$hazard_csr_vhdl_dep $hazard_vhdl/hazard3_csr.vhdl" \
            "$hazard_csr_verilog_dep $hazard_verilog/hazard3_csr.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' '' \
            "$configuration"
        or set failed 1
    end

    set -l hazard_csr_vhdl_dep \
        "$hazard_vhdl/hazard3_pkg.vhdl" \
        "$hazard_vhdl/hazard3_instr_decompress.vhdl" \
        "$hazard_vhdl/hazard3_decode.vhdl"

    set -l hazard_csr_verilog_dep \
        "$hazard_verilog/hazard3_instr_decompress.v" \
        "$hazard_verilog/hazard3_decode.v"

    # 1. Default baseline (all features disabled / default values)
    check_assert_reset_pair hazard3_frontend hazard3_frontend \
        "$hazard_csr_vhdl_dep $hazard_vhdl/hazard3_frontend.vhdl" \
        "$hazard_csr_verilog_dep $hazard_verilog/hazard3_frontend.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog"
    or set failed 1

    # 2. Orthogonal configurations covering the generate branches and parameter-dependent muxes:
    # - Config 1: No C/E: no_decompress branch, buf_level/hwvld masking, 32-bit-only alignment
    # - Config 2: Debug: instruction injection, trigger/check registers (break bits masked with C)
    # - Config 3: Debug without C: trigger break masks {C,1} = "01"
    # - Config 4: PMP + U-mode: PMP kill path, check registers without debug, jump_priv propagation
    # - Config 5: Branch predictor with C: BTB, overhanging branches, hwvld/predbranch marking
    # - Config 6: Branch predictor without C: BTB with word-aligned instructions only
    # - Config 7: Maximal feature set enabled (all concurrent paths)
    for configuration in \
        'EXTENSION_C=false EXTENSION_E=false' \
        'DEBUG_SUPPORT=true' \
        'DEBUG_SUPPORT=true EXTENSION_C=false' \
        'PMP_REGIONS=1 U_MODE=true' \
        'BRANCH_PREDICTOR=true' \
        'BRANCH_PREDICTOR=true EXTENSION_C=false' \
        'BRANCH_PREDICTOR=true DEBUG_SUPPORT=true PMP_REGIONS=2 U_MODE=true EXTENSION_C=true EXTENSION_E=false EXTENSION_M=true'

        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0' | string replace -a '=' '_')
        check_assert_reset_pair "hazard3_frontend_$configuration_name" hazard3_frontend \
            "$hazard_csr_vhdl_dep $hazard_vhdl/hazard3_frontend.vhdl" \
            "$hazard_csr_verilog_dep $hazard_verilog/hazard3_frontend.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' '' \
            "$configuration"
        or set failed 1
    end

    # 1. Default baseline (PMP_REGIONS=0: stubbed-out generate branch)
    check_assert_reset_pair hazard3_pmp hazard3_pmp \
        "$hazard_vhdl/hazard3_pkg.vhdl $hazard_vhdl/hazard3_pmp.vhdl" \
        "$hazard_verilog/hazard3_pmp.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog"
    or set failed 1

    # 2. Orthogonal configurations covering the generate branches and grain-dependent masks:
    # - Config 1: Single NAPOT/NA4 region, G=0
    # - Config 2: NAPOT with G=1: NA4 unsupported (mapped to OFF), pmpaddr read-back zeroing
    # - Config 3: NAPOT + TOR: TOR lock propagation to region i-1, prev_ge chaining
    # - Config 4: TOR only, G=2: regions span two pmpcfg registers, read-back ones-filling
    # - Config 5: 8 regions, NAPOT + TOR, G=3, Xh3pmpm disabled (pmpcfgm0 reads zero)
    # - Config 6: Maximum region count (all four pmpcfg registers, full pmpcfgm0 width)
    for configuration in \
        'PMP_REGIONS=1' \
        'PMP_REGIONS=3 PMP_GRAIN=1' \
        'PMP_REGIONS=4 PMP_MATCH_TOR=true' \
        'PMP_REGIONS=5 PMP_MATCH_NAPOT=false PMP_MATCH_TOR=true PMP_GRAIN=2' \
        'PMP_REGIONS=8 PMP_MATCH_TOR=true PMP_GRAIN=3 EXTENSION_XH3PMPM=false' \
        'PMP_REGIONS=16 PMP_MATCH_TOR=true'

        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0' | string replace -a '=' '_')
        check_assert_reset_pair "hazard3_pmp_$configuration_name" hazard3_pmp \
            "$hazard_vhdl/hazard3_pkg.vhdl $hazard_vhdl/hazard3_pmp.vhdl" \
            "$hazard_verilog/hazard3_pmp.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 5 \
            "$configuration"
        or set failed 1
    end
end

if test "$check_mode" = default

    set -l hazard_vhdl "$repo_root/hdl/modules/hazard4edu/vhdl"
    set -l hazard_verilog "$repo_root/hdl/modules/hazard4edu/verilog"

    # 1. Default baseline (PMP_REGIONS=0: stubbed-out generate branch)
    check_assert_reset_pair hazard3_pmp hazard3_pmp \
        "$hazard_vhdl/hazard3_pkg.vhdl $hazard_vhdl/hazard3_pmp.vhdl" \
        "$hazard_verilog/hazard3_pmp.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        "$hazard_verilog"
    or set failed 1

    # 2. Orthogonal configurations covering the generate branches and grain-dependent masks:
    # - Config 1: Single NAPOT/NA4 region, G=0
    # - Config 2: NAPOT with G=1: NA4 unsupported (mapped to OFF), pmpaddr read-back zeroing
    # - Config 3: NAPOT + TOR: TOR lock propagation to region i-1, prev_ge chaining
    # - Config 4: TOR only, G=2: regions span two pmpcfg registers, read-back ones-filling
    # - Config 5: 8 regions, NAPOT + TOR, G=3, Xh3pmpm disabled (pmpcfgm0 reads zero)
    # - Config 6: Maximum region count (all four pmpcfg registers, full pmpcfgm0 width)
    for configuration in \
        'PMP_REGIONS=1' \
        'PMP_REGIONS=3 PMP_GRAIN=1' \
        'PMP_REGIONS=4 PMP_MATCH_TOR=true' \
        'PMP_REGIONS=5 PMP_MATCH_NAPOT=false PMP_MATCH_TOR=true PMP_GRAIN=2' \
        'PMP_REGIONS=8 PMP_MATCH_TOR=true PMP_GRAIN=3 EXTENSION_XH3PMPM=false' \
        'PMP_REGIONS=16 PMP_MATCH_TOR=true'

        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0' | string replace -a '=' '_')
        check_assert_reset_pair "hazard3_pmp_$configuration_name" hazard3_pmp \
            "$hazard_vhdl/hazard3_pkg.vhdl $hazard_vhdl/hazard3_pmp.vhdl" \
            "$hazard_verilog/hazard3_pmp.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$hazard_verilog" \
            '' 5 \
            "$configuration"
        or set failed 1
    end
end

# We done! Print the result and return non-zero if a fail occurred somewhere
printf '\nResults: %s\n' $results_file
cat $results_file
deactivate  # Deactivate the oss-cad-suite shell
exit $failed