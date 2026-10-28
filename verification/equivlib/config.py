"""Loading, validation and expansion of the per-module equivalence.toml files."""

import hashlib
import itertools
import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

LEVELS = ("basic", "extensive")
MANIFEST_GLOB = "hdl/modules/*/verification/equivalence.toml"
MAX_ID_LENGTH = 200     # Test IDs are used as directory names, which are limited to 255 bytes

# Allowed keys per table. Anything else is reported as an error, so typos don't go unnoticed.
TOP_KEYS = {"module", "defaults", "filesets", "test"}
MODULE_KEYS = {"vhdl_dir", "verilog_dir", "include"}
DEFAULT_KEYS = {"reset", "sat_cycles"}
FILESET_KEYS = {"use", "vhdl", "verilog"}
TEST_KEYS = {"name", "top", "use", "vhdl", "verilog", "blackbox", "blackbox_instances", "reset",
             "sat_cycles", "generic_map", "basic", "extensive"}
EXTENSIVE_KEYS = {"matrix", "configs", "exclude"}


class ConfigError(Exception):
    """An equivalence.toml file is invalid or refers to something that does not exist."""


@dataclass
class EquivTest:
    """One fully resolved equivalence check: a design in a single generic configuration."""
    module: str
    id: str
    name: str
    top: str
    vhdl: list[Path]                # In analysis order, dependencies first
    verilog: list[Path]
    include: list[Path]             # Verilog include directories
    blackbox: list[Path]            # Verilog blackbox stubs for vendor primitives
    # Instances of the top level replaced by cut points, as (VHDL name, Verilog name) pairs.
    # VHDL names as in GHDL's netlist, Verilog names with generate scopes joined by '_'.
    blackbox_instances: list[tuple[str, str]]
    reset: dict[str, list[int]]     # Signal -> value at SAT step 1, 2, ...
    sat_cycles: int
    generics: dict[str, object]     # VHDL generic name -> value
    generic_map: dict[str, str]     # VHDL generic name -> Verilog parameter name, if they differ


def discover(repo_root: Path) -> dict[str, Path]:
    """Return {module name: manifest path} of all modules that have equivalence tests."""
    # .../hdl/modules/<module>/verification/equivalence.toml: parents[1] is the module folder
    return {path.parents[1].name: path for path in sorted(repo_root.glob(MANIFEST_GLOB))}


def load_module(name: str, manifest: Path, level: str) -> list[EquivTest]:
    """Load one module's manifest and expand it into the tests of the given level."""
    try:
        data = tomllib.loads(manifest.read_text())
    except tomllib.TOMLDecodeError as error:
        raise ConfigError(f"{manifest}: {error}") from None
    return _Module(name, manifest, data).tests(level)


def test_id(name: str, generics: dict[str, object]) -> str:
    """Build a file system friendly ID, e.g. hazard3_alu_EXTENSION_A_1."""
    parts = [name] + [f"{key}_{_format_value(value)}" for key, value in generics.items()]
    tid = re.sub(r"[^A-Za-z0-9_]+", "_", "_".join(parts)).strip("_")
    # Too long for a directory name: cut it and append a hash of the full ID, so it stays unique
    if len(tid) > MAX_ID_LENGTH:
        digest = hashlib.sha1(tid.encode()).hexdigest()[:8]
        tid = f"{tid[:MAX_ID_LENGTH - 9]}_{digest}"
    return tid


def _format_value(value: object) -> str:
    """Format a generic value for a test ID: booleans as 1/0, boolean lists as a bit string,
    raw { vhdl, verilog } values by their Verilog string, everything else (integers) with str()."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, list):
        return "".join("1" if bit else "0" for bit in value)
    if isinstance(value, dict):
        return value["verilog"]
    return str(value)


class _Module:
    """One module's equivalence.toml manifest, with methods to validate and expand it into tests."""
    def __init__(self, name: str, manifest: Path, data: dict):
        self.name = name
        self.manifest = manifest
        self.root = manifest.parents[1]     # The module folder; all paths in the TOML are relative to it
        self._check_keys(data, TOP_KEYS, "top level")

        # [module]: where the sources are
        module = self._table(data, "module", "top level")
        self._check_keys(module, MODULE_KEYS, "[module]")
        self.vhdl_dir = self.root / self._string(module.get("vhdl_dir", "vhdl"), "[module] vhdl_dir")
        self.verilog_dir = self.root / self._string(module.get("verilog_dir", "verilog"), "[module] verilog_dir")
        self.include = [self._dir(self.root / d, "[module] include")
                        for d in self._strings(module.get("include", []), "[module] include")]

        # [defaults]: used by every test that doesn't set the key itself
        defaults = self._table(data, "defaults", "top level")
        self._check_keys(defaults, DEFAULT_KEYS, "[defaults]")
        self.default_reset = self._reset(defaults.get("reset", {}), "[defaults]")
        self.default_cycles = self._cycles(defaults.get("sat_cycles", 12), "[defaults]")

        # [filesets.*] are only resolved when a test uses them; _resolved caches the result
        self.filesets = self._table(data, "filesets", "top level")
        self._resolved: dict[str, tuple[list[Path], list[Path]]] = {}

        # [[test]] entries stay raw dicts here, tests() validates and expands them
        self.specs = data.get("test", [])
        if not isinstance(self.specs, list) or not self.specs:
            self._fail("top level", "expected at least one [[test]] table")

    # --- Test expansion -------------------------------------------------------------------------

    def tests(self, level: str) -> list[EquivTest]:
        """Return the fully resolved tests of the given level (basic or extensive)."""
        tests: list[EquivTest] = []
        seen: set[str] = set()      # Test IDs of this module, to detect duplicates
        for index, spec in enumerate(self.specs):
            # 'where' says in error messages which part of the file is wrong: by position until
            # the name is known, then by name
            where = f"test #{index + 1}"
            if not isinstance(spec, dict):
                self._fail(where, "expected a table")
            name = self._string(spec.get("name"), f"{where} name")
            where = f"test '{name}'"
            self._check_keys(spec, TEST_KEYS, where)

            # Settings shared by all configurations of this test
            vhdl, verilog = self._files(spec, where)
            if not vhdl or not verilog:
                self._fail(where, "needs at least one VHDL and one Verilog file (directly or via 'use')")
            blackbox = [self._file(self.root / f, f"{where} blackbox")
                        for f in self._strings(spec.get("blackbox", []), f"{where} blackbox")]
            instances = self._instances(spec.get("blackbox_instances", []), f"{where} blackbox_instances")
            reset =self._reset(spec["reset"], where) if "reset" in spec else self.default_reset
            cycles = self._cycles(spec.get("sat_cycles", self.default_cycles), where)
            generic_map = self._table(spec, "generic_map", where)
            for vhdl_name, verilog_name in generic_map.items():
                self._string(verilog_name, f"{where} generic_map.{vhdl_name}")

            # One EquivTest per generic configuration of the requested level
            for generics in self._configurations(spec, level, where):
                tid = test_id(name, generics)
                if tid in seen:
                    self._fail(where, f"duplicate test ID '{tid}', give the test a different name")
                seen.add(tid)
                tests.append(EquivTest(
                    module=self.name, id=tid, name=name, top=self._string(spec.get("top", name), f"{where} top"),
                    vhdl=vhdl, verilog=verilog, include=self.include, blackbox=blackbox,
                    blackbox_instances=instances, reset=reset,
                    sat_cycles=cycles, generics=generics, generic_map=generic_map,
                ))
        return tests

    def _configurations(self, spec: dict, level: str, where: str) -> list[dict[str, object]]:
        """basic: one configuration. extensive: basic + matrix product + explicit configs, deduplicated."""
        configs = [self._generics(self._table(spec, "basic", where), f"{where} basic")]
        # Validated at both levels, so mistakes in [test.extensive] already show up at the basic level
        extensive = self._table(spec, "extensive", where)
        self._check_keys(extensive, EXTENSIVE_KEYS, f"{where} extensive")

        if level == "extensive":
            matrix = self._table(extensive, "matrix", f"{where} extensive")
            exclude = extensive.get("exclude", [])
            if not isinstance(exclude, list):
                self._fail(f"{where} extensive.exclude", "expected a list of tables")
            exclude = [self._generics(e, f"{where} extensive.exclude") for e in exclude]
            for key, values in matrix.items():
                if not isinstance(values, list) or not values:
                    self._fail(f"{where} extensive.matrix.{key}", "expected a non-empty list of values")
            # Every combination of the matrix values. Without the 'if matrix' guard, product() of
            # nothing would yield one empty combination, i.e. an extra check with default generics.
            for combination in itertools.product(*matrix.values()) if matrix else ():
                config = self._generics(dict(zip(matrix, combination)), f"{where} extensive.matrix")
                # Drop the combination if it contains all key/value pairs of any 'exclude' entry
                if not any(all(config.get(k) == v for k, v in e.items()) for e in exclude):
                    configs.append(config)

            explicit = extensive.get("configs", [])
            if not isinstance(explicit, list):
                self._fail(f"{where} extensive.configs", "expected a list of tables")
            configs += [self._generics(c, f"{where} extensive.configs") for c in explicit]

        # Remove duplicates (e.g. basic repeated in the matrix), keeping the first occurrence. The key
        # is independent of the key order; repr() makes lists hashable. Configurations that are only
        # effectively equal (one sets a generic to its default, the other omits it) are both kept.
        unique: dict[tuple, dict[str, object]] = {}
        for config in configs:
            unique.setdefault(tuple(sorted((k, repr(v)) for k, v in config.items())), config)
        return list(unique.values())

    # --- File sets ------------------------------------------------------------------------------

    def _files(self, table: dict, where: str, stack: tuple[str, ...] = ()) -> tuple[list[Path], list[Path]]:
        """Collect the VHDL and Verilog files of a test or fileset, used filesets first."""
        vhdl: list[Path] = []
        verilog: list[Path] = []
        # Files of the used filesets first (they are dependencies), each file only once. The zip
        # pairs our VHDL list with the fileset's VHDL files and our Verilog list with its Verilog files.
        for used in self._strings(table.get("use", []), f"{where} use"):
            for path_list, paths in zip((vhdl, verilog), self._fileset(used, where, stack)):
                path_list += [p for p in paths if p not in path_list]
        # Then the table's own files
        for f in self._strings(table.get("vhdl", []), f"{where} vhdl"):
            path = self._file(self.vhdl_dir / f, f"{where} vhdl")
            if path not in vhdl:
                vhdl.append(path)
        for f in self._strings(table.get("verilog", []), f"{where} verilog"):
            path = self._file(self.verilog_dir / f, f"{where} verilog")
            if path not in verilog:
                verilog.append(path)
        return vhdl, verilog

    def _fileset(self, name: str, where: str, stack: tuple[str, ...]) -> tuple[list[Path], list[Path]]:
        """Return the VHDL and Verilog files of a named fileset, resolving any 'use' references.

        'stack' holds the filesets currently being resolved, to detect filesets that use each other.
        """
        if name in stack:
            self._fail(where, f"filesets use each other in a cycle: {' -> '.join(stack + (name,))}")
        if name not in self._resolved:
            fileset = self.filesets.get(name)
            if not isinstance(fileset, dict):
                self._fail(where, f"unknown fileset '{name}' (known: {', '.join(self.filesets) or 'none'})")
            self._check_keys(fileset, FILESET_KEYS, f"[filesets.{name}]")
            self._resolved[name] = self._files(fileset, f"[filesets.{name}]", stack + (name,))
        return self._resolved[name]

    # --- Value validation -----------------------------------------------------------------------

    def _generics(self, table: object, where: str) -> dict[str, object]:
        """Return a table of VHDL generic name -> value, validating the types."""
        if not isinstance(table, dict):
            self._fail(where, "expected a table of GENERIC = value")
        for key, value in table.items():
            # Allowed: true/false, integers, lists of booleans (array generics) and raw values
            ok = (isinstance(value, (bool, int))
                  or (isinstance(value, list) and value and all(isinstance(v, bool) for v in value))
                  or (isinstance(value, dict) and set(value) == {"vhdl", "verilog"}
                      and all(isinstance(v, str) for v in value.values())))
            if not ok:
                self._fail(f"{where}.{key}", "expected a boolean, an integer, a list of booleans or "
                                             "{ vhdl = \"...\", verilog = \"...\" }")
        return dict(table)

    def _instances(self, value: object, where: str) -> list[tuple[str, str]]:
        """Return the blackboxed instances as (VHDL name, Verilog name) pairs, validating the types.
        Each entry is a name used on both sides, or { vhdl = "...", verilog = "..." } if they differ."""
        if not isinstance(value, list):
            self._fail(where, "expected a list of instance names")
        instances: list[tuple[str, str]] = []
        for entry in value:
            if isinstance(entry, str) and entry:
                instances.append((entry, entry))
            elif (isinstance(entry, dict) and set(entry) == {"vhdl", "verilog"}
                  and all(isinstance(v, str) and v for v in entry.values())):
                instances.append((entry["vhdl"], entry["verilog"]))
            else:
                self._fail(where, "expected instance names or { vhdl = \"...\", verilog = \"...\" } tables")
        # Duplicates would evert the same instance twice
        if len({vhdl for vhdl, _ in instances}) != len(instances):
            self._fail(where, "an instance is listed more than once")
        return instances

    def _reset(self, value: object, where: str) -> dict[str, list[int]]:
        """Return a table of signal name -> value at SAT step 1, 2, ..., validating the types."""
        if not isinstance(value, dict):
            self._fail(f"{where} reset", "expected a table of signal = [value at step 1, step 2, ...]")
        for signal, steps in value.items():
            # type() instead of isinstance(): booleans are ints in Python, but not valid here
            if not isinstance(steps, list) or not steps or not all(type(s) is int for s in steps):
                self._fail(f"{where} reset.{signal}", "expected a non-empty list of integers, e.g. [0, 1]")
        return dict(value)

    def _cycles(self, value: object, where: str) -> int:
        """Return the number of SAT cycles, validating that it is a positive integer."""
        if type(value) is not int or value < 1:
            self._fail(f"{where} sat_cycles", "expected a positive integer")
        return value

    def _table(self, parent: dict, key: str, where: str) -> dict:
        """Return parent[key], validating that it is a table; an empty table if the key is missing."""
        value = parent.get(key, {})
        if not isinstance(value, dict):
            self._fail(where, f"'{key}' must be a table")
        return value

    def _string(self, value: object, where: str) -> str:
        """Return a string value, validating that it is a non-empty string."""
        if not isinstance(value, str) or not value:
            self._fail(where, "expected a non-empty string")
        return value

    def _strings(self, value: object, where: str) -> list[str]:
        """Return a list of strings, validating that it is a list and every element a string."""
        if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
            self._fail(where, "expected a list of strings")
        return value

    def _file(self, path: Path, where: str) -> Path:
        """Return the absolute path of a file, validating that it exists."""
        if not path.is_file():
            self._fail(where, f"file not found: {path}")
        return path.resolve()

    def _dir(self, path: Path, where: str) -> Path:
        """Return the absolute path of a directory, validating that it exists."""
        if not path.is_dir():
            self._fail(where, f"directory not found: {path}")
        return path.resolve()

    def _check_keys(self, table: dict, allowed: set[str], where: str):
        """Check that a table only contains the allowed keys, otherwise fail."""
        unknown = sorted(set(table) - allowed)
        if unknown:
            self._fail(where, f"unknown key(s) {', '.join(unknown)} (allowed: {', '.join(sorted(allowed))})")

    def _fail(self, where: str, message: str):
        """Raise a ConfigError naming the file and the part of it that is wrong."""
        raise ConfigError(f"{self.manifest}: {where}: {message}")
