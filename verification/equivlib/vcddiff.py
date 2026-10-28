"""Analysis of a Yosys 'sat -dump_vcd' counterexample: which gold/gate signals differ, and since when.

In the counterexample, equiv_make has merged both designs into one module: every signal of the
Verilog reference ends in '_gold', every signal of the GHDL netlist in '_gate'. Both sides are
paired by name in stages, because the implementations use different naming conventions:

1. same name, ignoring case (VHDL is case-insensitive)
2. register naming: a trailing '_reg' (VHDL port) or '_r' (Hazard3) is ignored, so 'dst_ack' or
   'dst_ack_r' pairs with 'dst_ack_reg'. '_next' signals are next-state logic and are not stripped.
3. renamed instances: an instance path that only exists on one side (e.g. 'shifter' and
   'barrel_shifter_instance') is mapped to the one on the other side that shares the most signal
   names with it, then stages 1 and 2 are repeated

GHDL's anonymous nets (n123) and Yosys' internal nets ($auto$..., $procmux$...) can't be paired.
"""

import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

# A VCD signal name of one side, e.g. 'sync_req.sync_flops_gold' or 'n125_gate [32_1]'
# (bits 32..1 of n125). base = 'sync_req.sync_flops', side = 'gold', msb/lsb only for slices.
SIDED_NAME = re.compile(r"^(?P<base>.+)_(?P<side>gold|gate)(?: \[(?P<msb>\d+)_(?P<lsb>\d+)\])?$")
ANONYMOUS_LEAF = re.compile(r"^n\d+$")      # GHDL's names for unnamed nets
REGISTER_SUFFIX = re.compile(r"_(reg|r)$")  # Register suffixes: '_reg' (VHDL port), '_r' (Hazard3)
MIN_SHARED_NAMES = 2        # Signal names two instance paths must share to be treated as renamed
# A port declaration in GHDL's netlist header, e.g. 'output [31:0] src_prdata' -> ('output', 'src_prdata')
PORT = re.compile(r"\b(input|output|inout)\s+(?:wire\s+|reg\s+)?(?:\[[^\]]*\]\s*)?\\?([A-Za-z0-9_$]+)")


@dataclass
class Signal:
    """A signal in a VCD counterexample, with its values at each SAT step."""
    name: str                   # As in the VCD, without the leading backslash
    width: int
    values: list[str] = field(default_factory=list)     # One per SAT step, MSB first
    side: str = ""              # gold, gate or "" (unsided Yosys net)
    path: tuple[str, ...] = ()  # Instance path after flattening (lower case)
    leaf: str = ""              # Signal name inside its instance (lower case)
    lsb: int = 0                # Bit offset if Yosys split the signal into slices

    @property
    def display(self) -> str:
        """The name without the '_gold' / '_gate' suffix, for the report."""
        return self.name.rsplit("_", 1)[0] if self.side else self.name

    @property
    def slice(self) -> str:
        """'[msb:lsb]' if the signal is a slice of a wider one, otherwise ''."""
        return f"[{self.lsb + self.width - 1}:{self.lsb}]" if self.lsb else ""


@dataclass
class Pair:
    """A pair of signals from the gold and gate sides, with the way they were paired."""
    gold: Signal
    gate: Signal
    how: str                    # same name, register naming or renamed instance


@dataclass
class Analysis:
    """The result of analyzing a counterexample: the compared signals, unpaired signals and outputs."""
    steps: int                      # Number of SAT steps in the counterexample
    pairs: list[Pair]               # Gold/gate signals that are compared
    unpaired_gold: list[Signal]     # Gold signals without a gate counterpart (incl. Yosys internals)
    unpaired_gate: list[Signal]     # Gate signals without a gold counterpart (incl. GHDL's n123 nets)
    instance_map: dict[tuple[str, ...], tuple[str, ...]]   # Renamed instances: gold path -> gate path
    outputs: set[str]               # Output port names of the top level (lower case), empty if unknown

    def first_difference(self, pair: Pair) -> int | None:
        """Return the first SAT step where the pair differs, or None if they are equal."""
        for step in range(self.steps):
            if pair.gold.values[step] != pair.gate.values[step]:
                return step + 1
        return None


def analyze(vcd: Path, netlist: Path | None = None) -> Analysis:
    """Parse and pair a counterexample. 'netlist' (the GHDL Verilog output) identifies the outputs."""
    signals, steps = parse_vcd(vcd)
    # Only named signals of either side take part in the pairing
    gold = [s for s in signals if s.side == "gold" and _pairable(s)]
    gate = [s for s in signals if s.side == "gate" and _pairable(s)]
    pairs, instance_map = _pair(gold, gate)
    # Signal objects are compared by identity (id()): the dataclass would compare all values
    paired = {id(s) for p in pairs for s in (p.gold, p.gate)}
    return Analysis(
        steps=steps, pairs=pairs, instance_map=instance_map,
        unpaired_gold=[s for s in signals if s.side == "gold" and id(s) not in paired],
        unpaired_gate=[s for s in signals if s.side == "gate" and id(s) not in paired],
        outputs=_outputs(netlist) if netlist and netlist.is_file() else set(),
    )


def report(analysis: Analysis, vcd: Path, step: int | None = None, list_unpaired: bool = True) -> str:
    """Human readable report: first divergence (or the given step), timeline, unpaired signals."""
    a = analysis
    out: list[str] = []     # Report lines

    # Header: what could be compared and what not
    hows = Counter(p.how for p in a.pairs)
    anonymous = sum(1 for s in a.unpaired_gate if ANONYMOUS_LEAF.match(s.leaf))
    out.append(f"Counterexample analysis of {vcd.name}")
    out.append(f"  {a.steps} SAT steps, {len(a.pairs)} gold/gate signal pairs compared ("
               + ", ".join(f"{hows[h]} {h}" for h in ("same name", "register naming", "renamed instance"))
               + ")")
    out.append(f"  Not comparable: {len(a.unpaired_gold)} gold-only, {len(a.unpaired_gate)} gate-only signals "
               f"({anonymous} of them anonymous GHDL nets)")
    for gold_path, gate_path in sorted(a.instance_map.items()):
        out.append(f"  Renamed instance: {'.'.join(gold_path)} (gold) = {'.'.join(gate_path)} (gate)")

    # (first differing step, pair) of every pair that differs at all, earliest first
    timeline = sorted(((first, p) for p in a.pairs if (first := a.first_difference(p))),
                      key=lambda fp: (fp[0], fp[1].gold.display))
    if not timeline:
        out.append("\nNo compared signal pair differs. The difference is in signals that could not be paired,")
        out.append("open the VCD in a waveform viewer.")
    else:
        # Table of all pairs differing at the requested step, or at the first step with a difference
        shown = step or timeline[0][0]
        out.append(f"\n{'First divergence' if step is None else 'Differences'} at step {shown}:")
        rows = [(p.gold.display + p.gold.slice, p.gate.display + p.gate.slice,
                 _value(p.gold.values[shown - 1]), _value(p.gate.values[shown - 1]),
                 _bits(p.gold, p.gate, shown - 1))
                for p in a.pairs if p.gold.values[shown - 1] != p.gate.values[shown - 1]]
        out += _table(("gold", "gate", "gold value", "gate value", "differing bits"), rows) if rows \
            else ["  (none)"]
        # Internal signals usually diverge before the outputs; the first output divergence is where
        # the counterexample becomes visible from outside
        output_steps = [(f, p) for f, p in timeline if _is_output(p, a.outputs)]
        if output_steps:
            first = output_steps[0][0]
            names = ", ".join(p.gold.display for f, p in output_steps if f == first)
            out.append(f"First divergence at an output: step {first}: {names}")

        out.append("\nDivergence timeline (first differing step of each pair):")
        for first, p in timeline:
            gate_name = "" if p.how == "same name" else f" <-> {p.gate.display}"
            tags = [p.how] if p.how != "same name" else []
            if _is_output(p, a.outputs):
                tags.append("output")
            out.append(f"  step {first:>3}  {p.gold.display}{p.gold.slice}{gate_name}"
                       + (f"  ({', '.join(tags)})" if tags else ""))

    # Named signals that could not be paired: often renamed signals a human can match by eye
    if list_unpaired:
        for side, unpaired in (("gold", a.unpaired_gold), ("gate", a.unpaired_gate)):
            named = sorted({s.display for s in unpaired if _pairable(s)})
            if named:
                out.append(f"\nNamed {side}-only signals (not compared): {', '.join(named)}")
    return "\n".join(out) + "\n"


def parse_vcd(path: Path) -> tuple[list[Signal], int]:
    """Return the signals with one value per SAT step, and the number of steps.

    Yosys writes the initial state and step 1 at #0, step n at #n, and a final timestamp
    without values that only marks the end of the trace.
    """
    by_id: dict[str, Signal] = {}           # VCD identifier code (e.g. 'v12') -> signal
    current: dict[str, str] = {}            # Identifier -> latest value
    snapshots: list[dict[str, str]] = []    # Values of all signals at the end of each timestamp
    started = False                         # True after the first '#<time>' line
    with path.open() as f:
        for line in f:
            line = line.strip()
            if line.startswith("$var"):
                parts = line.split()
                # $var <type> <width> <id> <name...> $end, the name may contain a ' [msb_lsb]' slice
                by_id[parts[3]] = _signal(" ".join(parts[4:-1]), int(parts[2]))
            elif line.startswith("#"):
                # A new timestamp closes the previous one. The final timestamp is never closed and so
                # not counted, which drops the empty end marker.
                if started:
                    snapshots.append(dict(current))
                started = True
            elif line.startswith(("b", "B")):
                # Vector value: 'b<bits> <id>'
                value, ident = line[1:].split()
                current[ident] = value
            elif started and line[:1] in ("0", "1", "x", "X", "z", "Z"):
                # Scalar value: '<bit><id>'
                current[line[1:]] = line[0].lower()
    # One value per step and signal, padded to the full width: VCD may omit leading bits; they
    # are 0 if the first given bit is 0 or 1, otherwise copies of it (x or z)
    for snapshot in snapshots:
        for ident, signal in by_id.items():
            value = snapshot.get(ident, "x")
            signal.values.append(value.rjust(signal.width, "0" if value[0] in "01" else value[0]))
    return list(by_id.values()), len(snapshots)


def _signal(name: str, width: int) -> Signal:
    """Create a Signal from a VCD name, splitting it into side, instance path, leaf and slice."""
    name = name.lstrip("\\")
    m = SIDED_NAME.match(name)
    if not m:
        return Signal(name=name, width=width)   # Yosys net without a side, never paired
    # 'sync_req.sync_flops' -> path ('sync_req',), leaf 'sync_flops'; lower case for VHDL
    *path, leaf = m["base"].lower().split(".")
    return Signal(name=name if not m["msb"] else name.split(" ")[0], width=width, side=m["side"],
                  path=tuple(path), leaf=leaf, lsb=int(m["lsb"]) if m["lsb"] else 0)


def _pairable(s: Signal) -> bool:
    """True for named design signals; False for Yosys' internal nets and GHDL's anonymous nets."""
    # Yosys' internal nets ($auto$..., $procmux$...) appear with '$' replaced by '_' in the VCD. Their
    # names may contain source file paths with dots, so every part of the split name is checked.
    return not (any(part.startswith(("_", "$")) for part in (*s.path, s.leaf)) or ANONYMOUS_LEAF.match(s.leaf))


def _pair(gold: list[Signal], gate: list[Signal]):
    """Pair gold and gate signals in the stages described in the module docstring.

    Returns the pairs and the map of renamed instances (gold path -> gate path).
    """
    pairs: list[Pair] = []
    rest_gold, rest_gate = list(gold), list(gate)   # Signals not paired yet

    def match(key, how, mapping):
        """Pair the remaining signals whose key is equal on both sides, labelling the pairs 'how'.

        'key(signal, path)' builds the comparison key; gold paths are translated with 'mapping'
        (renamed instances) first. A pair also needs the same width on both sides.
        """
        nonlocal rest_gold, rest_gate
        keyed_gold, keyed_gate = _keyed(rest_gold, key, mapping), _keyed(rest_gate, key, {})
        for k in keyed_gold.keys() & keyed_gate.keys():
            g, s = keyed_gold[k], keyed_gate[k]
            if g.width == s.width:
                pairs.append(Pair(g, s, how))
        # Paired signals don't take part in the later stages
        done = {id(x) for p in pairs for x in (p.gold, p.gate)}
        rest_gold = [s for s in rest_gold if id(s) not in done]
        rest_gate = [s for s in rest_gate if id(s) not in done]

    # Comparison keys: (instance path, leaf name, slice offset), the leaf with or without register suffix
    exact = lambda s, path: (path, s.leaf, s.lsb)
    register = lambda s, path: (path, REGISTER_SUFFIX.sub("", s.leaf), s.lsb)
    match(exact, "same name", {})                   # Stage 1
    match(register, "register naming", {})          # Stage 2

    # Stage 3: the same two matches again, with renamed instances mapped (on all signals, so
    # instances are recognised by the names already paired in stages 1 and 2 as well)
    instance_map = _align_instances(gold, gate)
    if instance_map:
        match(exact, "renamed instance", instance_map)
        match(register, "renamed instance", instance_map)
    return pairs, instance_map


def _keyed(signals, key, mapping):
    """Key -> signal, without keys that several signals map to (e.g. both 'x' and 'x_r' exist)."""
    keys = [(key(s, mapping.get(s.path, s.path)), s) for s in signals]
    counts = Counter(k for k, _ in keys)
    return {k: s for k, s in keys if counts[k] == 1}


def _align_instances(gold: list[Signal], gate: list[Signal]) -> dict[tuple[str, ...], tuple[str, ...]]:
    """Map instance paths that only exist on one side to their counterpart with the most shared names."""
    def leaves(signals):
        """Instance path -> set of its signal names (register suffix removed)."""
        result: dict[tuple[str, ...], set[str]] = {}
        for s in signals:
            result.setdefault(s.path, set()).add(REGISTER_SUFFIX.sub("", s.leaf))
        return result
    gold_paths, gate_paths = leaves(gold), leaves(gate)
    # (shared names, gold path, gate path) for every gold-only/gate-only path pair of the same
    # depth, most shared names first
    candidates = sorted(
        ((len(gold_paths[g] & gate_paths[s]), g, s)
         for g in gold_paths.keys() - gate_paths.keys()
         for s in gate_paths.keys() - gold_paths.keys() if len(g) == len(s)),
        reverse=True)
    # Greedy: take the best candidates first; each path is mapped at most once
    mapping: dict[tuple[str, ...], tuple[str, ...]] = {}
    for shared, g, s in candidates:
        if shared >= MIN_SHARED_NAMES and g not in mapping and s not in mapping.values():
            mapping[g] = s
    return mapping


def _outputs(netlist: Path) -> set[str]:
    """Output port names of the top module in GHDL's Verilog netlist, which is named like the file."""
    text = netlist.read_text(errors="replace")
    # The module header: from 'module <top>' to the first ');', which closes the port list
    module = re.search(rf"^module\s+\\?{re.escape(netlist.stem)}\b(.*?)\);", text, re.MULTILINE | re.DOTALL)
    if not module:
        return set()
    return {name.lower() for direction, name in PORT.findall(module[1]) if direction == "output"}


def _is_output(pair: Pair, outputs: set[str]) -> bool:
    """True if the pair is an output port of the top level (signals inside instances never are)."""
    return not pair.gold.path and pair.gold.leaf in outputs


def _value(bits: str) -> str:
    """Format a value for the report: single bits as is, vectors as zero-padded hex, '0b...' with x/z."""
    if len(bits) == 1:
        return bits
    if set(bits) <= {"0", "1"}:
        return f"0x{int(bits, 2):0{(len(bits) + 3) // 4}x}"
    return f"0b{bits}"


def _bits(gold: Signal, gate: Signal, step: int) -> str:
    """Differing bit indices as compact ranges, e.g. '31:28, 3'."""
    if gold.width == 1:
        return "-"
    a, b = gold.values[step], gate.values[step]
    # The strings are MSB first: character i is bit (width - 1 - i), shifted by the slice offset
    indices = [gold.lsb + gold.width - 1 - i for i in range(gold.width) if a[i] != b[i]]
    ranges: list[list[int]] = []    # [high, low] per run of neighbouring bits
    for index in indices:       # Descending
        # Extend the current run if this bit is directly below it, otherwise start a new run
        if ranges and ranges[-1][1] == index + 1:
            ranges[-1][1] = index
        else:
            ranges.append([index, index])
    return ", ".join(f"{hi}:{lo}" if hi != lo else str(hi) for hi, lo in ranges)


def _table(header: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    """Format the header and rows as left-aligned columns, each as wide as its longest entry."""
    widths = [max(len(str(r[i])) for r in (header, *rows)) for i in range(len(header))]
    return ["  " + "  ".join(str(c).ljust(w) for c, w in zip(r, widths)).rstrip() for r in (header, *rows)]
