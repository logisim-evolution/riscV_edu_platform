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

if not contains -- $check_mode default full debug
    printf 'Usage: %s [full|debug]\n' (status filename) >&2
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
    for generic_value in (string split ' ' -- $generic_values)
        set -a vhdl_generic_args "-g$generic_value"
        set -l parameter (string split '=' -- $generic_value)
        set -l verilog_value $parameter[2]
        if test "$verilog_value" = true
            set verilog_value 1
        else if test "$verilog_value" = false
            set verilog_value 0
        end
        set verilog_chparam "$verilog_chparam chparam -set $parameter[1] $verilog_value gold;"
    end
    set -l verilog_include ''
    if test -n "$verilog_include_dir"
        set verilog_include "-I$verilog_include_dir"
    end

    # Create folder if it doesn't exist already
    mkdir -p "$build_dir/$name" $work_dir
    printf '\n=== %s (reset-constrained assertions) ===\n' $name | tee $log_file

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
        read_verilog -formal $silver_file                   # Read in the GHDL synthesized netlist
        rename $top silver                                  # Rename netlist top module to 'silver'
        proc; memory; async2sync                            # Standard synthesis pre-processing passes
        equiv_make -make_assert gold silver equiv           # Create equivalence checking module
        prep -top equiv                                     # Prepare the new 'equiv' module as top
        flatten; async2sync; opt                            # Flatten hierarchy, optimize, and map clocks to logic
        sat $sat_options -seq $sat_cycles -verify -prove-asserts -set-init-zero $reset_constraints   # Run SAT solver with optional reset constraints
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
        "$repo_root/hdl/modules/debug/vhdl/cdc/hazard3_sync_1bit.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/cdc/hazard3_sync_1bit.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1"
    or set failed 1

    check_assert_reset_pair hazard3_reset_sync hazard3_reset_sync \
        "$repo_root/hdl/modules/debug/vhdl/cdc/hazard3_reset_sync.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/cdc/hazard3_reset_sync.v" \
        "-set-at 1 rst_n_in 0 -set-at 2 rst_n_in 1"
    or set failed 1

    check_assert_reset_pair hazard3_apb_async_bridge hazard3_apb_async_bridge \
        "$repo_root/hdl/modules/debug/vhdl/cdc/hazard3_sync_1bit.vhdl $repo_root/hdl/modules/debug/vhdl/cdc/hazard3_apb_async_bridge.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/cdc/hazard3_sync_1bit.v $repo_root/hdl/modules/debug/verilog/cdc/hazard3_apb_async_bridge.v" \
        "-set-at 1 rst_n_src 0 -set-at 1 rst_n_dst 0 -set-at 2 rst_n_src 1 -set-at 2 rst_n_dst 1"
    or set failed 1

    check_assert_reset_pair hazard3_sbus_to_ahb hazard3_sbus_to_ahb \
        "$repo_root/hdl/modules/debug/vhdl/dm/hazard3_sbus_to_ahb.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/dm/hazard3_sbus_to_ahb.v"
    or set failed 1

    check_assert_reset_pair hazard3_dm hazard3_dm \
        "$repo_root/hdl/modules/debug/vhdl/dm/hazard3_dm.vhdl" \
        "$repo_root/hdl/modules/debug/verilog/dm/hazard3_dm.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        '' '' \
        "8"
    or set failed 1

    # The JTAG debug modules have the following files as common dependency.
    set -l dtm_vhdl "$repo_root/hdl/modules/debug/vhdl/cdc/hazard3_sync_1bit.vhdl $repo_root/hdl/modules/debug/vhdl/cdc/hazard3_apb_async_bridge.vhdl $repo_root/hdl/modules/debug/vhdl/dtm/hazard3_jtag_dtm_core.vhdl"
    set -l dtm_verilog "$repo_root/hdl/modules/debug/verilog/cdc/hazard3_sync_1bit.v $repo_root/hdl/modules/debug/verilog/cdc/hazard3_apb_async_bridge.v $repo_root/hdl/modules/debug/verilog/dtm/hazard3_jtag_dtm_core.v"

    check_assert_reset_pair hazard3_jtag_dtm_core hazard3_jtag_dtm_core "$dtm_vhdl" "$dtm_verilog" \
        "-set-at 1 trst_n 0 -set-at 1 rst_n_dmi 0 -set-at 2 trst_n 1 -set-at 2 rst_n_dmi 1"
    or set failed 1

    check_assert_reset_pair hazard3_jtag_dtm hazard3_jtag_dtm \
        "$dtm_vhdl $repo_root/hdl/modules/debug/vhdl/dtm/hazard3_jtag_dtm.vhdl" \
        "$dtm_verilog $repo_root/hdl/modules/debug/verilog/dtm/hazard3_jtag_dtm.v" \
        "-set-at 1 trst_n 0 -set-at 1 rst_n_dmi 0 -set-at 2 trst_n 1 -set-at 2 rst_n_dmi 1"
    or set failed 1

    check_assert_reset_pair hazard3_ecp5_jtag_dtm hazard3_ecp5_jtag_dtm \
        "$dtm_vhdl $repo_root/hdl/modules/debug/vhdl/dtm/hazard3_ecp5_jtag_dtm.vhdl" \
        "$dtm_verilog $repo_root/hdl/modules/debug/verilog/dtm/hazard3_ecp5_jtag_dtm.v" \
        "-set-at 1 rst_n_dmi 0 -set-at 2 rst_n_dmi 1" \
        '' \
        "$repo_root/verification/ecp5_jtagg_blackbox.v"
    or set failed 1

    set -a dtm_vhdl "$repo_root/hdl/modules/debug/vhdl/cdc/hazard3_reset_sync.vhdl $repo_root/hdl/modules/debug/vhdl/dtm/hazard3_ecp5_jtag_dtm.vhdl $repo_root/hdl/modules/debug/vhdl/dm/hazard3_dm.vhdl"
    set -a dtm_verilog "$repo_root/hdl/modules/debug/verilog/cdc/hazard3_reset_sync.v $repo_root/hdl/modules/debug/verilog/dtm/hazard3_ecp5_jtag_dtm.v $repo_root/hdl/modules/debug/verilog/dm/hazard3_dm.v"

    check_assert_reset_pair hazard3_dm_ecp5 hazard3_dm_ecp5 \
        "$dtm_vhdl $repo_root/hdl/modules/debug/vhdl/hazard3_dm_ecp5.vhdl" \
        "$dtm_verilog $repo_root/hdl/modules/debug/verilog/hazard3_dm_ecp5.v" \
        "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
        '' \
        "$repo_root/verification/ecp5_jtagg_blackbox.v" \
    or set failed 1
end

# =============================================================================
# |                     HAZARD4EDU EQUIVALENCE CHECKS                         |
# =============================================================================

if test "$check_mode" = default -o "$check_mode" = full
    set -l hazard_alu_vhdl "$repo_root/hdl/modules/hazard4edu/vhdl/hazard3_pkg.vhdl"
    set -l hazard_alu_verilog ''

    check_assert_reset_pair hazard3_shift_barrel hazard3_shift_barrel \
        "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_shift_barrel.vhdl" \
        "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_shift_barrel.v" \
        '' \
        "$repo_root/hdl/modules/hazard4edu/verilog"
    or set failed 1

    check_assert_reset_pair hazard3_branchcmp hazard3_branchcmp \
        "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_branchcmp.vhdl" \
        "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_branchcmp.v" \
        '' \
        "$repo_root/hdl/modules/hazard4edu/verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_encode hazard3_onehot_encode \
        "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_onehot_encode.vhdl" \
        "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_onehot_encode.v" \
        '' \
        "$repo_root/hdl/modules/hazard4edu/verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_priority hazard3_onehot_priority \
        "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_onehot_priority.vhdl" \
        "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_onehot_priority.v" \
        '' \
        "$repo_root/hdl/modules/hazard4edu/verilog"
    or set failed 1

    check_assert_reset_pair hazard3_onehot_priority_dynamic hazard3_onehot_priority_dynamic \
        "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_onehot_priority.vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_onehot_priority_dynamic.vhdl" \
        "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_onehot_priority.v $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_onehot_priority_dynamic.v" \
        '' \
        "$repo_root/hdl/modules/hazard4edu/verilog"
    or set failed 1

    set -a hazard_alu_vhdl "$repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_shift_barrel.vhdl"
    set -a hazard_alu_verilog "$repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_shift_barrel.v"

    for configuration in \
        'EXTENSION_A=false' \
        'EXTENSION_A=true' 
        set configuration_name (string replace -a ' ' '_' -- $configuration | string replace -a '=true' '_1' | string replace -a '=false' '_0')
        check_assert_reset_pair "hazard3_alu_$configuration_name" hazard3_alu \
            "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_alu.vhdl" \
            "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_alu.v" \
            '' \
            "$repo_root/hdl/modules/hazard4edu/verilog" \
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
            "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_muldiv_seq.vhdl" \
            "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_muldiv_seq.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$repo_root/hdl/modules/hazard4edu/verilog" \
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
            "$hazard_alu_vhdl $repo_root/hdl/modules/hazard4edu/vhdl/arith/hazard3_mul_fast.vhdl" \
            "$hazard_alu_verilog $repo_root/hdl/modules/hazard4edu/verilog/arith/hazard3_mul_fast.v" \
            "-set-at 1 rst_n 0 -set-at 2 rst_n 1" \
            "$repo_root/hdl/modules/hazard4edu/verilog" \
            '' 2 \
            "$configuration"
        or set failed 1
    end
end

# We done! Print the result and return non-zero if a fail occurred somewhere
printf '\nResults: %s\n' $results_file
cat $results_file
deactivate  # Deactivate the oss-cad-suite shell
exit $failed