#!/usr/bin/env python3
"""Gate: the Flutter endpoint registry matches the pinned dsh Remote surface.

`flutter/packages/harness_adapter/lib/src/rpc_map.dart` (`DshRpcEndpoints`) is
the client's half of the wire contract; `reference/deepseek-harness/` at the
commit `reference/README.md` records is the other half. Nothing else compares
them: the adapter's fake-host suite derives its accepted names from the same
registry it is supposed to police, so a renamed wire name folds onto the old
constant and the suite stays green. This gate is that missing comparison.

Derivation source (the reviewed choice)
---------------------------------------
0.1.2 deleted the static `packages/host/apiproxy/src/api/rpc-map.ts` registry;
0.1.5 registers methods as `@Remote(...)` decorators on `TypertRemoteService`
subclasses, and the wire endpoint is composed at build time by the Typert
generator as `<namespace>/<exportName>` (`packages/typert/protocol/src/index.ts`
`Remote`, `bindTypertRemote`). No committed file carries the composed endpoint
literals — `workspaceFiles/readBytes` exists nowhere as a string. The gate
therefore scans declaration sites, which is the registration itself:

  * every `class X extends TypertRemoteService` under
    `reference/deepseek-harness/packages/**/src/**/*.ts` (a `tests` path
    component is skipped: generator fixtures contain decoy declarations),
  * the `super(ctx, <serviceKey>[, { namespace }])` call that binds the wire
    namespace (`this.typertRemote = bindTypertRemote(...)`),
  * each line-anchored `@Remote` / `@Remote('export')` /
    `@Remote({ mode: 'stream' })` decorator and the method it decorates
    (bare `@Remote` exports the method name; an object argument marks a
    logical stream, which is not a unary endpoint constant),
  * the Gateway's own `$events/result` constant
    (`packages/api/gateway/src/stream-protocol.ts`), which is a Remote method
    but not a decorator.

`fixture.ts` was rejected as the source: it is the upstream *client's* fake,
and it omits endpoints the 0.1.5 host does register
(`workspaceFiles/readBytes`, `workspaceFiles/readAll`). Deriving from it would
report a drift that does not exist. The bundle composition
(`packages/bundle/*/cordis.patch.yml`) is closer to one deployment's loaded
set but is a patch-overlay parse with no clean library here; the declaration
scan is deployment-independent and a superset of every composition.

Normalisation and allowlist
---------------------------
Exactly one normalisation is applied to both sides: surrounding whitespace is
trimmed. Case and separators stay significant on purpose — folding
`skill/list`, `skill.list`, and `skills/list` is the drift this gate exists to
catch, so the comparison never does it.

Names the client declares that the pin does not register live in
`gates_manifest.json` (`wire_pin.declared_only_allowlist`, one reviewed reason
each), and that excuse is only valid while the name is *declared and not
invoked*: a declaration the client never calls is inert, while a call to a
route the pin does not serve is a defect. The allowlist is closed in three
directions:

  * a client endpoint that is neither registered nor allowlisted fails;
  * an allowlisted name the pin now registers fails (remove the entry), so
    drift cannot silently re-open;
  * an allowlisted name that is invoked from
    `flutter/packages/harness_adapter/lib/src/**` fails, naming the call site,
    so the gate cannot bless a live call to a non-existent route.

Privileged / loopback classification
------------------------------------
0.1.1 carried `PRIVILEGED_METHODS` in `packages/client/connection/src/index.ts`
and refused every member off loopback. 0.1.5 removed it: the browser-trust
fence (`isTrustedApiRequest`) and the signed browser-session cookie now apply
to every `/api` method uniformly, and the surviving concept is
`ctx.connection.isLoopback` (consumed by the Web UI, not by a per-method
guard). There is therefore no privileged-method list to classify in this pin.
The gate does not skip that: it asserts the mechanism's shape (the identifier
must be absent *and* the surviving fence/isLoopback facts must be present),
fails loudly if a privileged set reappears without the gate being extended,
and validates the client's own out-of-scope list — the machine-readable
coverage block in `docs/spec.md` — against the derived surface.

Documented limitations
----------------------
* The scan covers the whole pinned tree, so a method registered only by a
  package the `dsh web` bundle does not mount (today `agentTeams/*`) counts as
  upstream. That is a deliberate superset: it cannot false-fail the client,
  but it could let a client call to an unmounted namespace pass.
* A method registered by a runtime-built binding (not a literal
  `super(ctx, '<key>')` in a source file) is invisible; an unparsable
  declaration fails the gate loudly instead of being dropped.
* Streams (`@Remote({ mode: 'stream' })`) are counted but excluded from the
  unary comparison; the client registry holds no stream constant.
* The pin is checked at the submodule's *checked-out* commit
  (`git -C reference/deepseek-harness rev-parse HEAD`), not the parent's
  recorded gitlink.

Usage: python3 scripts/verify_wire_pin.py [--print-digest]
Exit code 0 = registry, pin identity, classification, counts, declared-only
invocation, and test-double honesty all agree; 1 = violations found (each
printed with file:line).
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"
CLIENT_REGISTRY: Path = REPO / "flutter/packages/harness_adapter/lib/src/rpc_map.dart"
ADAPTER_LIB_DIR: Path = REPO / "flutter/packages/harness_adapter/lib/src"
ADAPTER_TEST_DIR: Path = REPO / "flutter/packages/harness_adapter/test"
PIN_README: Path = REPO / "reference" / "README.md"
PIN_ROOT: Path = REPO / "reference" / "deepseek-harness"
CONNECTION_SRC: Path = PIN_ROOT / "packages/client/connection/src"
GATEWAY_PROTOCOL: Path = PIN_ROOT / "packages/api/gateway/src/stream-protocol.ts"
SPEC: Path = REPO / "docs/spec.md"
README: Path = REPO / "README.md"

CLIENT_CONST = re.compile(r"static\s+const\s+String\s+(\w+)\s*=\s*")

CLIENT_VALUE = re.compile(r"(?:\s|//[^\n]*\n)*r?'([^']*)'\s*;")
CLASS_DECL = re.compile(
    r"^\s*(?:export\s+)?(?:abstract\s+)?class\s+(\w+)\s+extends\s+TypertRemoteService\b"
)
SUPER_BIND = re.compile(r"super\(\s*ctx\s*,\s*'([^']+)'\s*(?:,\s*\{([^}]*)\})?\s*\)")
NAMESPACE = re.compile(r"namespace\s*:\s*'([^']+)'")
REMOTE_DECORATOR = re.compile(r"^\s*@Remote(?:\(|$)")
REMOTE_ARGUMENT = re.compile(r"^\s*@Remote\(\s*(.*?)\s*\)\s*$")
METHOD_DECL = re.compile(
    r"^\s*(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*([A-Za-z_$][\w$]*)\s*\("
)
STREAM_DECORATOR = re.compile(r"mode\s*:\s*'stream'")
GATEWAY_CONST = re.compile(r"export\s+const\s+REMOTE_EVENT_RESULT_ENDPOINT\s*=\s*'([^']+)'")
PIN_COMMIT = re.compile(r"Pinned commit:\s*`([0-9a-f]{40})`")
PIN_DIGEST = re.compile(r"Registration-source digest:\s*`([0-9a-f]{64})`")
README_COVERAGE = re.compile(r"Coverage today is (\d+) of (\d+)")
COVERAGE_BEGIN = "<!-- wire-pin:coverage:begin -->"
COVERAGE_END = "<!-- wire-pin:coverage:end -->"
WIRE_NAME = re.compile(r"^[A-Za-z0-9_$.-]+/[A-Za-z0-9_$.-]+$")

COUNT_KEYS = ("declared", "upstream", "identical", "missing", "client-only")


class Violations:
    """Ordered, de-duplicated file:line violations."""

    def __init__(self) -> None:
        self.items: list[str] = []

    def add(self, location: str, message: str) -> None:
        entry = f"{location}: {message}"
        if entry not in self.items:
            self.items.append(entry)

    def __bool__(self) -> bool:
        return bool(self.items)


def client_endpoints(violations: Violations) -> dict[str, tuple[int, str]]:
    """Wire name -> (line, constant name) for every `DshRpcEndpoints` constant."""
    if not CLIENT_REGISTRY.exists():
        violations.add(str(CLIENT_REGISTRY.relative_to(REPO)), "client registry is missing")
        return {}
    lines = CLIENT_REGISTRY.read_text(encoding="utf-8").splitlines()
    rel = CLIENT_REGISTRY.relative_to(REPO).as_posix()
    start = next((i for i, line in enumerate(lines) if "class DshRpcEndpoints" in line), None)
    if start is None:
        violations.add(rel, "no `class DshRpcEndpoints` — the registry moved or was renamed")
        return {}
    depth = 0
    in_class = False
    body_lines: list[str] = []
    for line in lines[start:]:
        depth += line.count("{") - line.count("}")
        if "{" in line and not in_class:
            in_class = True
            continue
        if not in_class:
            continue
        if depth <= 0:
            break
        body_lines.append(line)
    body = "\n".join(body_lines)
    found: dict[str, tuple[int, str]] = {}
    for match in CLIENT_CONST.finditer(body):
        literal = CLIENT_VALUE.match(body, match.end())
        line = body.count("\n", 0, match.start()) + start + 2
        if literal is None:
            violations.add(f"{rel}:{line}", f"unparsed endpoint constant `{match.group(1)}`")
            continue
        found[literal.group(1)] = (line, match.group(1))
    if not found:
        violations.add(rel, "extracted zero endpoint constants from DshRpcEndpoints")
    return found


def allowlisted_invocation_violations(
    client: dict[str, tuple[int, str]],
    declared_only: dict[str, str],
    violations: Violations,
) -> None:
    """Fail an allowlisted name that the wire layer actually invokes.

    The allowlist excuses a declaration the client never calls. An invocation
    is a live call to a route the pin does not serve, so the entry is a defect
    to remove — the check is deliberate about the distinction the old
    always-excuse framing blurred.
    """
    if not declared_only:
        return
    sources = [
        path
        for path in ADAPTER_LIB_DIR.rglob("*.dart")
        if path != CLIENT_REGISTRY
    ]
    for name in sorted(declared_only):
        entry = client.get(name)
        if entry is None:
            continue
        constant = entry[1]
        reference = f"DshRpcEndpoints.{constant}"
        literals = (f"'{name}'", f'"{name}"')
        for path in sorted(sources):
            rel = path.relative_to(REPO).as_posix()
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                if reference in line or any(literal in line for literal in literals):
                    violations.add(
                        f"{rel}:{number}",
                        f"`{name}` is in wire_pin.declared_only_allowlist but is invoked here — "
                        "a call to a route the pinned tree does not register is a defect to remove, "
                        "not an exception to keep",
                    )


def pin_source_files() -> list[Path]:
    """TypeScript source files that can carry a Typert Remote registration."""
    files = [
        path
        for path in (PIN_ROOT / "packages").rglob("*.ts")
        if "src" in path.parts and "tests" not in path.parts
    ]
    return sorted(files)


def pin_endpoints(violations: Violations) -> tuple[dict[str, str], set[str], set[Path]]:
    """Unary endpoint -> 'file:line (method)', streams, and contributing files."""
    if not PIN_ROOT.is_dir():
        violations.add("reference/deepseek-harness", "pinned submodule is not checked out")
        return {}, set(), set()
    unary: dict[str, str] = {}
    streams: set[str] = set()
    contributing: set[Path] = set()
    for path in pin_source_files():
        rel = path.relative_to(REPO).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        namespace: str | None = None
        class_line: int | None = None
        binding_line: int | None = None
        for index, line in enumerate(lines):
            declaration = CLASS_DECL.match(line)
            if declaration:
                if class_line is not None and binding_line is None:
                    violations.add(
                        f"{rel}:{class_line}",
                        "a TypertRemoteService subclass has no parsable "
                        "`super(ctx, '<key>')` binding — extend the gate",
                    )
                namespace, class_line, binding_line = None, index + 1, None
                continue
            if class_line is not None and binding_line is None:
                if "super(" in line:
                    binding = SUPER_BIND.search(line)
                    if binding is None:
                        violations.add(
                            f"{rel}:{index + 1}",
                            "unparsable `super(...)` binding on a TypertRemoteService — "
                            f"extend the gate: {line.strip()}",
                        )
                        binding_line = index + 1
                        continue
                    option = NAMESPACE.search(binding.group(2) or "")
                    namespace = option.group(1) if option else binding.group(1)
                    binding_line = index + 1
                    continue
            decorator = REMOTE_DECORATOR.match(line)
            if not decorator:
                continue
            if namespace is None or binding_line is None:
                violations.add(
                    f"{rel}:{index + 1}",
                    "@Remote decorator outside a parsed TypertRemoteService class — extend the gate",
                )
                continue
            argument = REMOTE_ARGUMENT.match(line)
            decorator_argument = argument.group(1) if argument else None
            method_line: int | None = None
            method_name: str | None = None
            for probe in range(index + 1, min(index + 9, len(lines))):
                candidate = lines[probe]
                if not candidate.strip() or candidate.lstrip().startswith(("@", "//", "*", "/*")):
                    continue
                method = METHOD_DECL.match(candidate)
                if method:
                    method_name, method_line = method.group(1), probe + 1
                break
            if method_name is None or method_line is None:
                violations.add(
                    f"{rel}:{index + 1}",
                    "@Remote decorator with no parsable decorated method — extend the gate",
                )
                continue
            stream = decorator_argument is not None and STREAM_DECORATOR.search(decorator_argument) is not None
            if stream:
                export = method_name
            elif decorator_argument is not None:
                export = decorator_argument.strip("'\"")
            else:
                export = method_name
            endpoint = f"{namespace}/{export}"
            contributing.add(path)
            if stream:
                streams.add(endpoint)
            else:
                unary[endpoint] = f"{rel}:{method_line} ({method_name})"
        if class_line is not None and binding_line is None:
            violations.add(
                f"{rel}:{class_line}",
                "a TypertRemoteService subclass has no parsable "
                "`super(ctx, '<key>')` binding — extend the gate",
            )
    gateway_rel = GATEWAY_PROTOCOL.relative_to(REPO).as_posix()
    if GATEWAY_PROTOCOL.exists():
        constant = GATEWAY_CONST.search(GATEWAY_PROTOCOL.read_text(encoding="utf-8"))
        if constant is None:
            violations.add(gateway_rel, "no `REMOTE_EVENT_RESULT_ENDPOINT` constant — extend the gate")
        else:
            unary[constant.group(1)] = f"{gateway_rel} (REMOTE_EVENT_RESULT_ENDPOINT)"
            contributing.add(GATEWAY_PROTOCOL)
    else:
        violations.add(gateway_rel, "Gateway stream-protocol.ts is missing")
    if not unary:
        violations.add(gateway_rel, "derived zero registered endpoints — extend the gate")
    return unary, streams, contributing


def registration_digest(files: set[Path]) -> str:
    """sha256 over `relpath\\0bytes\\0` for each contributing file, sorted by path."""
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.relative_to(PIN_ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def submodule_head(violations: Violations) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(PIN_ROOT), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        violations.add("reference/deepseek-harness", f"cannot read the submodule HEAD ({error})")
        return None
    if result.returncode != 0 or not result.stdout.strip():
        violations.add(
            "reference/deepseek-harness",
            f"git rev-parse HEAD failed (exit {result.returncode}); "
            "run `git submodule update --init reference/deepseek-harness`",
        )
        return None
    return result.stdout.strip()


def coverage_block(violations: Violations) -> tuple[dict[str, object], dict[str, int]]:
    """Parse the machine-readable coverage block from docs/spec.md."""
    rel = SPEC.relative_to(REPO).as_posix()
    if not SPEC.exists():
        violations.add(rel, "spec is missing")
        return {}, {}
    lines = SPEC.read_text(encoding="utf-8").splitlines()
    begin = next((i for i, line in enumerate(lines) if line.strip() == COVERAGE_BEGIN), None)
    end = next((i for i, line in enumerate(lines) if line.strip() == COVERAGE_END), None)
    if begin is None or end is None or end < begin:
        violations.add(
            rel,
            f"no `{COVERAGE_BEGIN}` / `{COVERAGE_END}` coverage block — the gate reads its counts here",
        )
        return {}, {}
    block: dict[str, object] = {}
    line_of: dict[str, int] = {}
    for offset, line in enumerate(lines[begin + 1 : end], start=begin + 2):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            violations.add(f"{rel}:{offset}", f"coverage line is not `key = value`: {stripped}")
            continue
        key, value = (part.strip() for part in stripped.split("=", 1))
        if key == "out-of-scope":
            block[key] = [item.strip() for item in value.split(",") if item.strip()]
            line_of[key] = offset
        elif key in COUNT_KEYS:
            if not value.isdigit():
                violations.add(f"{rel}:{offset}", f"coverage count `{key}` is not an integer: {value}")
            else:
                block[key] = int(value)
                line_of[key] = offset
        else:
            violations.add(f"{rel}:{offset}", f"unknown coverage key `{key}`")
    missing = [key for key in COUNT_KEYS if key not in block]
    if "out-of-scope" not in block:
        missing.append("out-of-scope")
    if missing:
        violations.add(
            f"{rel}:{begin + 1}",
            f"coverage block is missing key(s): {', '.join(missing)}",
        )
    return block, line_of


def privileged_endpoints(violations: Violations) -> set[str] | None:
    """Return None when this pin carries no privileged-method set (asserted)."""
    sources = sorted(CONNECTION_SRC.rglob("*.ts")) if CONNECTION_SRC.is_dir() else []
    if not sources:
        violations.add(
            CONNECTION_SRC.relative_to(REPO).as_posix(),
            "connection source is missing — cannot classify the privileged surface",
        )
        return None
    marker: Path | None = None
    text_by_path: dict[Path, str] = {}
    for path in sources:
        text = path.read_text(encoding="utf-8")
        text_by_path[path] = text
        if "PRIVILEGED_METHODS" in text:
            marker = path
    if marker is None:
        # 0.1.5 shape: no per-method pin. Assert the surviving mechanism, loudly.
        client_ref = CONNECTION_SRC / "client" / "index.ts"
        host_ref = CONNECTION_SRC / "rpc-host.ts"
        if not client_ref.exists() or "isLoopback" not in text_by_path.get(client_ref, ""):
            violations.add(
                client_ref.relative_to(REPO).as_posix(),
                "no `PRIVILEGED_METHODS` set AND no `connection.isLoopback` — "
                "the privileged-surface concept is gone; extend the gate before trusting a pin bump",
            )
        if not host_ref.exists() or "isTrustedApiRequest(" not in text_by_path.get(host_ref, ""):
            violations.add(
                host_ref.relative_to(REPO).as_posix(),
                "no `PRIVILEGED_METHODS` set AND no `isTrustedApiRequest(` fence — "
                "the request gate moved; extend the gate before trusting a pin bump",
            )
        return None
    rel = marker.relative_to(REPO).as_posix()
    body = marker.read_text(encoding="utf-8")
    set_match = re.search(r"PRIVILEGED_METHODS\s*=\s*new\s+Set\(\[(.*?)\]\)", body, re.DOTALL)
    if set_match is None:
        violations.add(
            f"{rel}:1",
            "`PRIVILEGED_METHODS` is present but has no parsable `new Set([...])` — extend the gate",
        )
        return set()
    names = {name for name in re.findall(r"'([^']+)'", set_match.group(1)) if WIRE_NAME.match(name)}
    if not names:
        violations.add(
            f"{rel}:1",
            "`PRIVILEGED_METHODS` parsed to zero method names — extend the gate",
        )
    return names


def test_double_violations(violations: Violations) -> None:
    """Fail if the adapter suite reintroduces a name-folding registry map."""
    if not ADAPTER_TEST_DIR.is_dir():
        violations.add(ADAPTER_TEST_DIR.relative_to(REPO).as_posix(), "adapter test directory is missing")
        return
    fold_name = re.compile(r"(?i)(legacy|variant|alias|fold|canonical).*(map|table|aliases)")
    map_open = re.compile(r"(?:Map\s*<[^>]*>|<String\s*,[^>]*>)\s*(?==)|\bMap\s*<[^>]*>\s*\w+\s*=")
    for path in sorted(ADAPTER_TEST_DIR.rglob("*.dart")):
        rel = path.relative_to(REPO).as_posix()
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for number, line in enumerate(lines, start=1):
            for name in re.findall(r"\b(\w+)\s*=", line):
                if fold_name.search(name):
                    violations.add(
                        f"{rel}:{number}",
                        f"`{name}` looks like a name-folding registry map; the fake host must accept "
                        "exactly the DshRpcEndpoints names, not fold variants",
                    )
        for match in map_open.finditer(text):
            brace = text.find("{", match.end())
            if brace == -1:
                continue
            depth, cursor = 0, brace
            while cursor < len(text):
                if text[cursor] == "{":
                    depth += 1
                elif text[cursor] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                cursor += 1
            literal = text[brace : cursor + 1]
            line_number = text.count("\n", 0, match.start()) + 1
            if "DshRpcEndpoints." in literal and re.search(r"'[A-Za-z0-9_$.-]+/[A-Za-z0-9_$.-]+'", literal):
                violations.add(
                    f"{rel}:{line_number}",
                    "map literal mixes DshRpcEndpoints constants with wire-name string literals — "
                    "a folding double hides rpc_map.dart renames",
                )
        for number, line in enumerate(lines, start=1):
            case = re.match(r"\s*case\s+'([A-Za-z0-9_$.-]+/[A-Za-z0-9_$.-]+)'", line)
            if case is None:
                continue
            window = "\n".join(lines[max(0, number - 3) : number + 2])
            if "DshRpcEndpoints." in window:
                violations.add(
                    f"{rel}:{number}",
                    f"`case '{case.group(1)}'` folds a wire-name literal onto DshRpcEndpoints — "
                    "the fake host must reject undeclared names instead",
                )


def check(print_digest: bool = False) -> int:
    violations = Violations()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    wire_pin: dict[str, object] = manifest.get("wire_pin", {})
    declared_only: dict[str, str] = wire_pin.get("declared_only_allowlist", {})  # type: ignore[assignment]

    client = client_endpoints(violations)
    upstream, streams, contributing = pin_endpoints(violations)
    digest = registration_digest(contributing)

    if print_digest:
        if violations:
            print("WIRE-PIN GATE: cannot print a digest from a broken derivation:")
            for violation in violations.items:
                print(f"  {violation}")
            return 1
        print(digest)
        return 0

    # -- 1. registry <-> registry ------------------------------------------
    for name, (line, _constant) in sorted(client.items()):
        if name in upstream:
            if name in declared_only:
                violations.add(
                    f"{CLIENT_REGISTRY.relative_to(REPO).as_posix()}:{line}",
                    f"`{name}` is allowlisted as declared-only but the pin registers it at "
                    f"{upstream[name]} — drop the wire_pin.declared_only_allowlist entry",
                )
        elif name not in declared_only:
            violations.add(
                f"{CLIENT_REGISTRY.relative_to(REPO).as_posix()}:{line}",
                f"`{name}` is registered nowhere under reference/deepseek-harness and is not in "
                "wire_pin.declared_only_allowlist",
            )
    for name in sorted(declared_only):
        if name not in client:
            violations.add(
                "scripts/gates_manifest.json:wire_pin.declared_only_allowlist",
                f"`{name}` is allowlisted but no DshRpcEndpoints constant declares it — "
                "remove or fix the entry",
            )
    allowlisted_invocation_violations(client, declared_only, violations)

    # -- 2. pin identity ---------------------------------------------------
    pin_rel = PIN_README.relative_to(REPO).as_posix()
    if not PIN_README.exists():
        violations.add(pin_rel, "pin record is missing")
    else:
        pin_text = PIN_README.read_text(encoding="utf-8")
        commit = PIN_COMMIT.search(pin_text)
        recorded = PIN_DIGEST.search(pin_text)
        if commit is None:
            violations.add(pin_rel, "no `Pinned commit:` line — record the pin")
        if recorded is None:
            violations.add(
                pin_rel,
                "no `Registration-source digest:` line — record the derived surface digest",
            )
        head = submodule_head(violations)
        if commit is not None and head is not None and commit.group(1) != head:
            violations.add(
                pin_rel,
                f"records pin {commit.group(1)[:12]} but the submodule is checked out at "
                f"{head[:12]} — re-pin the record or the submodule",
            )
        if recorded is not None and recorded.group(1) != digest:
            violations.add(
                pin_rel,
                f"records registration digest {recorded.group(1)[:12]}… but the declared source hashes "
                f"to {digest[:12]}… — a pin bump must update the record "
                "(python3 scripts/verify_wire_pin.py --print-digest)",
            )

    # -- 3. privileged / loopback classification ---------------------------
    block, block_line = coverage_block(violations)
    privileged = privileged_endpoints(violations)
    out_of_scope = [str(name) for name in block.get("out-of-scope", [])]
    spec_rel = SPEC.relative_to(REPO).as_posix()
    for name in out_of_scope:
        if name not in upstream:
            violations.add(spec_rel, f"out-of-scope `{name}` is registered nowhere in the pinned tree")
        if name in client:
            violations.add(
                f"{spec_rel}: coverage block",
                f"out-of-scope `{name}` is wired by DshRpcEndpoints — drop it from the out-of-scope list "
                "or stop declaring it",
            )
    if privileged:
        for name in sorted(privileged):
            if name not in client and name not in out_of_scope:
                violations.add(
                    "reference/deepseek-harness: packages/client/connection/src",
                    f"privileged method `{name}` is neither wired by DshRpcEndpoints nor named in "
                    f"{spec_rel}'s out-of-scope list",
                )

    # -- 4. derived doc counts --------------------------------------------
    identical = sorted(set(client) & set(upstream))
    missing = sorted(set(upstream) - set(client))
    client_only = sorted(set(client) - set(upstream))
    derived = {
        "declared": len(client),
        "upstream": len(upstream),
        "identical": len(identical),
        "missing": len(missing),
        "client-only": len(client_only),
    }
    if README.exists():
        readme_text = README.read_text(encoding="utf-8")
        coverage = README_COVERAGE.search(readme_text)
        if coverage is None:
            violations.add(
                README.relative_to(REPO).as_posix(),
                "no `Coverage today is <identical> of <upstream>` sentence — the gate reads its counts here",
            )
        else:
            line = readme_text.count("\n", 0, coverage.start()) + 1
            if (int(coverage.group(1)), int(coverage.group(2))) != (derived["identical"], derived["upstream"]):
                violations.add(
                    f"{README.relative_to(REPO).as_posix()}:{line}",
                    f"states {coverage.group(1)} of {coverage.group(2)} but the registries give "
                    f"{derived['identical']} of {derived['upstream']}",
                )
    else:
        violations.add(README.relative_to(REPO).as_posix(), "README is missing")
    for key in COUNT_KEYS:
        recorded = block.get(key)
        if isinstance(recorded, int) and recorded != derived[key]:
            violations.add(
                f"{spec_rel}:{block_line.get(key, 1)}",
                f"coverage block records {key} = {recorded} but the registries give {derived[key]}",
            )

    # -- 5. test-double honesty -------------------------------------------
    test_double_violations(violations)

    if violations:
        print(f"WIRE-PIN GATE: violations found ({len(violations.items)}):")
        for violation in violations.items:
            print(f"  {violation}")
        return 1
    privileged_note = "present" if privileged else "absent (asserted)"
    print(
        "WIRE-PIN GATE: CLEAN "
        f"(declared {derived['declared']}, upstream {derived['upstream']}, "
        f"identical {derived['identical']}, missing {derived['missing']}, "
        f"client-only {derived['client-only']}, streams {len(streams)}, "
        f"privileged-set {privileged_note})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(check("--print-digest" in sys.argv[1:]))
