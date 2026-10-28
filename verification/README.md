# Formal equivalence checks

The VHDL modules in `hdl/modules/` are ports of Verilog reference designs (mostly Hazard3). These
checks prove formally that both implementations behave identically:

1. GHDL synthesizes the VHDL design to a Verilog netlist (*silver*).
2. Yosys reads the reference Verilog (*gold*), builds a miter of both and proves with its SAT solver
   that all outputs are equal for a number of clock cycles after reset.

Requirements: Python 3.14 or newer (standard library only) and the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) in `/opt/oss-cad-suite`
(or wherever `OSS_CAD_SUITE` points), or `ghdl` and `yosys` on `PATH`. Without a local
installation, `--env docker` runs everything in a container instead (see [Docker](#docker)).

## Running

```sh
verification/equiv.py --all                          # every module (final sign-off, CI)
verification/equiv.py debug hazard4edu               # selected modules
hdl/modules/hazard4edu/verification/run.py           # one module, from its own folder
```

| Option                | Meaning                                                                                                                                                                                                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--level basic`     | One configuration per test (default), for quick feedback while developing                                                                                                                                                                                                             |
| `--level extensive` | Every configuration listed in the TOML files, for sign-off                                                                                                                                                                                                                            |
| `-j N`              | Number of checks run in parallel (default: all CPU threads but about one in six, at least one; e.g. 20 of 24, 7 of 8)                                                                                                                                                                 |
| `-t NAME`           | Only the test with exactly this `name` from `equivalence.toml`, in all configurations of the chosen level. Repeatable                                                                                                                                                             |
| `-k PATTERN`        | Only checks whose `module/id` contains `PATTERN`, or matches it if it has `*?[` wildcards. Repeatable                                                                                                                                                                           |
| `--list`            | Show the selected checks without running them                                                                                                                                                                                                                                         |
| `--check`           | Validate the TOML files and print the GHDL/Yosys commands without running them                                                                                                                                                                                                        |
| `--vcd`             | Dump the counterexample of a failing proof, with all signals of gold and silver, to `<top>_counterexample.vcd` next to the log (e.g. for GTKWave). Passing proofs have no counterexample, so they write no file. Without `--vcd`, the log of a failing proof lists only the ports |
| `--fail-fast`       | Start no new checks after the first failure                                                                                                                                                                                                                                           |
| `--timeout S`       | Time limit in seconds per check                                                                                                                                                                                                                                                       |
| `--env ENV`         | `auto` (default: OSS CAD Suite, then `PATH`, then prompts to fall back to Docker if neither is found), `native`, `path` or `docker` (run in a container, see [Docker](#docker))                                                                  |
| `--oss-cad-suite V` | With `--env docker`: OSS CAD Suite release, `latest` or a date `YYYY-MM-DD` (default: `$OSS_CAD_SUITE_VERSION`, else `latest`)                                                                                                                                       |
| `--rebuild-image`   | With `--env docker`: rebuild the image, e.g. to update a `latest` image                                                                                                                                                                                               |

Exit codes: `0` everything proven, `1` at least one check failed, `2` invalid arguments or TOML
file, `3` no GHDL/Yosys available (or Docker missing / image build failed).

Status of a check: `proven`, `ghdl-synth-failed`, `equivalence-failed` (the SAT solver found a
counterexample), `timeout`, `killed` (GHDL or Yosys was terminated by a signal, e.g. by hand or by
the out-of-memory killer, so nothing was disproven) or `error` (e.g. the top-level entity was not found).

Artifacts of each check land in `verification/build/<module>/<test id>/`: the GHDL netlist, the
generated `equivalence.ys` script (re-run it by hand with `yosys -s equivalence.ys`) and the log.
`verification/build/results.csv` summarizes the last run, `toolchain.txt` records the tool versions.
Only the directories of the checks being run are replaced.

## Docker

`--env docker` needs only Docker (and Python 3.14+ on the host to start the runner):

```sh
verification/equiv.py --all --env docker                              # newest OSS CAD Suite release
verification/equiv.py --all --env docker --oss-cad-suite 2026-10-23   # pinned release
OSS_CAD_SUITE_VERSION=2026-10-23 hdl/modules/debug/verification/run.py --env docker
```

The first use of a version builds the image `riscv-edu-equiv:oss-cad-suite-<version>` from
`verification/docker/` (downloads about 750 MB, 2.8 GB on disk). The whole runner then runs
inside the container with the same arguments, as your user, with the repository mounted at the
same path, so results land in `verification/build/` as usual. A `latest` image is not updated by
itself: the run prints when it was built, and `--rebuild-image` fetches the newest release.
Details: [docker/README.md](docker/README.md).

### Auto fallback

When `--env auto` (the default) cannot find GHDL/Yosys locally, it prompts before falling back
to Docker. `--list` and `--check` never trigger the prompt because they need no tools. There is
no prompt, and the run fails with exit code `3`, if Docker is missing, its daemon can't be
reached, or there is no interactive terminal to answer on (e.g. in CI); pass `--env docker` there
to use Docker without asking.

## Debugging a failing check

Re-run it with `--vcd`, e.g. `hdl/modules/debug/verification/run.py -t hazard3_dm --vcd`. The
counterexample is analysed right away: the report is printed, appended to the log and saved as
`<top>_divergence.txt`. It lists the first SAT step at which gold (Verilog) and gate (VHDL) signals
differ, the differing bits, the first differing output, and when each signal pair first diverges:

```
First divergence at step 9:
  gold                gate                    gold value   gate value   differing bits
  dst_prdata_pslverr  dst_prdata_pslverr_reg  0x000880001  0x000880000  0
First divergence at an output: step 12: src_pslverr
```

The earliest diverging signal is usually closest to the bug. The analysis can be repeated, also
for another step, with `verification/vcd_diff.py <vcd> [--step N]`.

The signals are paired by name in stages, because the implementations name things differently:
the same name ignoring case; then ignoring a register suffix `_reg` (VHDL) or `_r` (Hazard3), so
`dst_ack` and `dst_ack_r` pair with `dst_ack_reg`; then instances that are named differently
(e.g. `shifter` and `barrel_shifter_instance`) are recognised by the signal names they share.
Signals that were renamed otherwise (e.g. `sum` and `sum_of_a_and_b`), GHDL's anonymous nets
(`n123`) and Yosys' internal nets can't be paired. The report lists the named ones, and the VCD
(e.g. in GTKWave) contains all of them.

## Adding tests: `equivalence.toml`

Each module with checks has a `verification/` folder containing `equivalence.toml` and the
`run.py` launcher (copy it from another module, it needs no changes). The module is found
automatically. All paths are relative to the module folder.

```toml
[module]                          # optional
vhdl_dir    = "vhdl"              # base folder of 'vhdl' file entries (default "vhdl")
verilog_dir = "verilog"           # base folder of 'verilog' file entries (default "verilog")
include     = ["verilog"]         # Verilog `include directories

[defaults]                        # optional, applies to every test that doesn't set its own
reset      = { rst_n = [0, 1] }   # signal = [value at SAT step 1, step 2, ...]
sat_cycles = 12                   # number of clock cycles to prove (default 12)

[filesets.pkg]                    # named groups of files that tests (or other filesets) can 'use'
vhdl = ["hazard3_pkg.vhdl"]

[[test]]
name    = "hazard3_alu"           # also the top-level entity/module, unless 'top' is given
use     = ["pkg"]                 # filesets, in dependency order; their files come first
vhdl    = ["arith/hazard3_alu.vhdl"]
verilog = ["arith/hazard3_alu.v"]
reset   = {}                      # combinational: no reset sequence
[test.basic]                      # the configuration of the 'basic' level
EXTENSION_A = true
[test.extensive.matrix]           # every combination is checked at the 'extensive' level
EXTENSION_A = [false, true]
```

Per test, the following keys are available:

| Key                            | Meaning                                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `name`                       | Test name, prefix of the test IDs. Required                                                             |
| `top`                        | Top-level entity/module name, defaults to `name`                                                      |
| `use`, `vhdl`, `verilog` | Source files, dependencies first. The VHDL list must contain the top-level entity                       |
| `blackbox`                   | Verilog stubs for vendor primitives (adds `-ignore-unknown-cells` to the SAT solver)                  |
| `blackbox_instances`         | Instances of the top level to blackbox, so only their wiring is proven, see [Blackboxed instances](#blackboxed-instances) |
| `reset`, `sat_cycles`      | Override the `[defaults]`                                                                             |
| `generic_map`                | `{ VHDL_NAME = "VERILOG_NAME" }` for generics that are named differently in the Verilog reference     |
| `basic`                      | Generics of the basic level. Without it, the defaults of the entity/module are used, so they must agree |
| `extensive.matrix`           | `GENERIC = [values]`, the full product of all listed generics is checked                              |
| `extensive.exclude`          | List of partial configurations to remove from the matrix, e.g. illegal combinations                     |
| `extensive.configs`          | List of additional hand-picked configurations (`[[test.extensive.configs]]` tables)                   |

The extensive level runs the basic configuration, the matrix and the configs, without duplicates.
Generics not listed in a configuration keep the entity/module default; matrix and configs do not
inherit from `basic`.

Generic values:

| TOML                                                           | VHDL                                    | Verilog       |
| -------------------------------------------------------------- | --------------------------------------- | ------------- |
| `true` / `false`                                           | `true` / `false`                    | `1` / `0` |
| `4`                                                          | `4`                                   | `4`         |
| `[true, false, false]` (boolean_vector, highest index first) | `(2 => true, 1 => false, 0 => false)` | `3'b100`    |
| `{ vhdl = "x\"0000_0200\"", verilog = "32'h200" }`           | as given                                | as given      |

GHDL cannot set array generics on the command line, so for those the runner analyses a copy of the
top-level VHDL file with the generic's default value replaced (in the test's `ghdl-work/` folder).

### Blackboxed instances

Large designs built from units that already have their own tests (e.g. `hazard3_core`) can be
proven much faster by blackboxing those units. In both designs, `expose -evert` replaces each listed
instance of the top level by cut points: its outputs become inputs shared by gold and silver (free
values in every cycle) and its inputs become compared outputs, named `<instance>:<port>`. The proof
then covers only the logic around the instances and how they are wired, for every possible
behaviour of the instances. Their contents are left to their own tests.

```toml
blackbox_instances = [
    "frontend",                                                           # same name in both
    { vhdl = "branchcmp_gen_branchcmp_u", verilog = "fast_branchcmp_branchcmp_u" },  # names differ
]
```

- Names are those of GHDL's netlist: VHDL labels in lower case, with generate labels joined by `_`
  (e.g. `has_muldiv_muldiv`). On the Verilog side Yosys' `<scope>.<instance>` names of generate
  blocks are converted to the same form, so a mapping is only needed if the labels differ.
- Instances that a configuration does not generate are skipped (the log notes them).
- Port names and widths of an instance must agree between VHDL and Verilog. A blackboxed instance
  that exists in only one of the designs makes the check fail.
- Because the instances may behave arbitrarily, a difference in logic that only real instances would
  hide (e.g. a `'X'` default that the real decoder never selects) shows up as a counterexample.

# AI Disclosure

The python / toml verification scripts were assisted by a local hosted [Qwen3.6-35B-A3B-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) model at 4-bit quantization (UD-Q4-K-XL). `qwen code` and `hermes agent` were used as frontend and tools-provider to interface with the model and the repository. Detailed information about the architecture of the verification scripts can be found in the `memory/` folder. The model was used to assist in the creation of the verification scripts, including generating code snippets, providing suggestions for code structure, and offering insights into potential optimizations. The use of AI in this context was aimed at enhancing productivity and ensuring code quality, while all final decisions and implementations were made by human developers.

The following parameters were used to run the model, barely fitting on an 8GB VRAM GPU (larger context window would be helpful, but that would require more VRAM or even more, slow CPU RAM offloading):

```Shell
llama-server \
        --metrics \
        -m ~/models/Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
        --alias "qwen3.6-local" \
        -c 262144 \
        --load-mode none \
        --gpu-layers all \
        --cpu-moe \
        -fa on \
        -ctk q8_0 -ctv q8_0 \
        -t 12 \
        -b 512 -ub 512 \
        --jinja \
        --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \
        --host 127.0.0.1 --port 8080 \
        --path /run/media/Games/AI/monitor
```
