#!/usr/bin/env python3
"""Upstream askama shell templates -> MoonBit render functions (the templates/*_gen.mbt generator).

Template syntax supported (the askama subset jumbit needs, aligned with upstream templates/*.txt):
- {%- let name = "value" -%} / {%- decl name -%}: string bindings; decl pre-declares
- {%- if cond -%} / {%- else if cond -%} / {%- else -%} / {%- endif -%}
  cond ∈ {echo, resolve_symlinks, hook ==/!= InitHook::X, cfg!(windows)}
  a whole cfg!(windows) branch is dropped (jumbit is Linux-only; the README notes the difference)
- {%- match cmd %} / {%- when Some with (cmd) %} / {%- when None %} / {%- endmatch %}
- {%- match hook %} / {%- when InitHook::X %} (rendered as jumbit's Hook enum)
- {{ name }}: variable interpolation
- whitespace control: {%- / -%} strip all adjacent whitespace (askama semantics); the right boundary is found quote-aware

Renames (applied uniformly to text and string values, in the order given): __zoxide_->__jumbit_,
_ZO_-> _JB_, zoxide->jumbit, z#->j#; the output is then normalized through `moon fmt`.

Usage:
  gen_templates.py --src ~/repos-other/zoxide/templates --shell bash --out templates/bash_gen.mbt
  gen_templates.py --src ... --shell bash --stdout   # regression comparison mode
Regression check: regenerate bash/zsh and diff byte for byte against the committed files (the post-moon-fmt shape).
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field

RENAMES = [
    ("ajeetdsouza/zoxide", "superbigcup325/jumbit"),
    ("__zoxide_", "__jumbit_"),
    ("_ZO_", "_JB_"),
    ("zoxide", "jumbit"),
    ("z#", "j#"),
]
HOOK_MAP = {"None": "HookNone", "Prompt": "HookPrompt", "Pwd": "HookPwd"}


def rename(text: str) -> str:
    for old, new in RENAMES:
        text = text.replace(old, new)
    return text


# ------------------------------------------------------------ lexer


@dataclass
class Token:
    kind: str  # text / expr / stmt
    value: str  # text content / expression name / raw statement


def tokenize(tpl: str) -> list[Token]:
    """Split into text/expr/stmt; find the right boundary quote-aware; apply askama whitespace control."""
    tokens: list[Token] = []
    pos = 0
    n = len(tpl)

    def find_expr_close(start: int, close_pat: str) -> int:
        # two expression shapes: a string literal {{ "..." }} (the right boundary is the literal's
        # closing quote) or a plain identifier/unwrap (found with a quote-aware scan)
        i = start
        while i < n and tpl[i] in " \t":
            i += 1
        if i < n and tpl[i] == '"':
            j = i + 1
            while j < n:
                if tpl[j] == "\\":
                    j += 2
                    continue
                if tpl[j] == '"':
                    break
                j += 1
            k = j + 1
            while k < n and tpl[k] in " \t":
                k += 1
            if tpl.startswith(close_pat, k):
                return k
        return find_close(start, "{{", close_pat)

    def find_close(start: int, open_pat: str, close_pat: str) -> int:
        # scan for close_pat from start, skipping quoted literals (template bodies contain }} etc.)
        i = start
        quote = ""
        while i < n - 1:
            c = tpl[i]
            if quote:
                if c == "\\":
                    i += 2
                    continue
                if c == quote:
                    quote = ""
                i += 1
                continue
            if c in "'\"":
                quote = c
                i += 1
                continue
            if tpl.startswith(close_pat, i):
                return i
            i += 1
        raise ValueError(f"unterminated {open_pat} (offset {start})")

    while pos < n:
        # an askama comment {#- ... -#} / {# ... #}: skip the whole block
        cmt = tpl.find("{#", pos)
        cand = []
        for open_pat, close_pat, kind in (("{%", "%}", "stmt"), ("{{", "}}", "expr")):
            idx = tpl.find(open_pat, pos)
            if idx != -1:
                cand.append((idx, open_pat, close_pat, kind))
        if cmt != -1 and (not cand or cmt < min(cand)[0]):
            cend = tpl.find("#}", cmt)
            assert cend != -1, "unterminated {#"
            if cmt > pos:
                tokens.append(Token("text", tpl[pos:cmt]))
            pos = cend + 2
            continue
        if not cand:
            tokens.append(Token("text", tpl[pos:]))
            break
        idx, open_pat, close_pat, kind = min(cand)
        if idx > pos:
            tokens.append(Token("text", tpl[pos:idx]))
        body_start = idx + 2
        if kind == "expr":
            end = find_expr_close(body_start, close_pat)
        else:
            end = find_close(body_start, open_pat, close_pat)
        body = tpl[body_start:end]
        pos = end + 2
        # whitespace control: only {%- strips the preceding text's trailing whitespace; under askama's
        # preserve mode -%} does not strip on the right (the committed generator output is the reference)
        trim_left = body.startswith("-")
        if trim_left:
            body = body[1:]
        if body.endswith("-"):
            body = body[:-1]
        body = body.strip()
        if trim_left and tokens and tokens[-1].kind == "text":
            tokens[-1].value = tokens[-1].value.rstrip()
        if kind == "expr":
            tokens.append(Token("expr", body))
        else:
            tokens.append(Token("stmt", body))
    return tokens


# ----------------------------------------------------------- syntax tree


@dataclass
class Node:
    pass


@dataclass
class Text(Node):
    value: str


@dataclass
class Expr(Node):
    name: str


@dataclass
class Let(Node):
    name: str
    value: str | None  # None = decl


@dataclass
class If(Node):
    # arms: [(raw cond or None for else, body)]
    arms: list = field(default_factory=list)


@dataclass
class Match(Node):
    expr: str  # cmd / hook
    # arms: [(raw pattern, binding name or None, body)]
    arms: list = field(default_factory=list)


def parse(tokens: list[Token]) -> list[Node]:
    pos = 0

    def parse_block(stop: set[str]) -> tuple[list[Node], str | None, list[str]]:
        nonlocal pos
        out: list[Node] = []
        while pos < len(tokens):
            tok = tokens[pos]
            if tok.kind == "text":
                if tok.value:
                    out.append(Text(rename(tok.value)))
                pos += 1
            elif tok.kind == "expr":
                out.append(Expr(tok.value))
                pos += 1
            else:
                stmt = tok.value
                if stmt.startswith("else if") and "else if" in stop:
                    return out, "else if", stmt.split()
                head = stmt.split()[0] if stmt.split() else ""
                if head in stop:
                    return out, head, stmt.split()
                if head == "let":
                    m = re.match(r"let\s+(\w+)\s*=\s*(.*)$", stmt, re.S)
                    out.append(Let(m.group(1), m.group(2).strip()))
                    pos += 1
                elif head == "decl":
                    out.append(Let(stmt.split()[1], None))
                    pos += 1
                elif head == "if" and stmt.startswith("if let Some"):
                    pos += 1
                    m2 = re.match(r"if let Some\((\w+)\)\s*=\s*(\w+)$", stmt)
                    body, term, _ = parse_block({"endif"})
                    pos += 1  # consume endif
                    assert term == "endif"
                    nm = m2.group(1)
                    out.append(
                        Match(
                            m2.group(2),
                            [(f"Some({nm})", nm, body), ("None", None, [])],
                        )
                    )
                elif head == "if":
                    pos += 1
                    node = parse_if(stmt)
                    out.append(node)
                elif head == "match":
                    pos += 1
                    out.append(parse_match(stmt))
                else:
                    raise ValueError(f"unknown statement (stop={stop}): {stmt}")
        return out, None, []

    def parse_if(cond: str) -> Node:
        nonlocal pos
        arms = []
        cur_cond = lower_cond(cond)
        while True:
            body, terminator, parts = parse_block({"endif", "else", "else if"})
            pos += 1  # consume the terminator (else if / else / endif)
            arms.append((cur_cond, body))
            if terminator == "endif":
                return If(arms)
            if terminator == "else":
                body2, term2, _ = parse_block({"endif"})
                pos += 1  # consume endif
                assert term2 == "endif"
                arms.append((None, body2))
                return If(arms)
            # else if <cond>：parts = ['else', 'if', ...cond...]
            cur_cond = lower_cond(" ".join(parts[2:]))

    def lower_cond(cond: str) -> str | None:
        cond = cond.strip()
        if cond.startswith("if "):
            cond = cond[3:]
        if cond.startswith("("):
            cond = cond[1:-1]
        if cond.startswith("cfg!(windows)"):
            return "DROP_WINDOWS"
        if cond == "cfg!(windows) ":
            return "DROP_WINDOWS"
        cond = cond.replace("InitHook::", "")
        m = re.match(r"hook\s*==\s*(\w+)$", cond)
        if m:
            return f"hook is {HOOK_MAP[m.group(1)]}"
        m = re.match(r"hook\s*!=\s*(\w+)$", cond)
        if m:
            return f"!(hook is {HOOK_MAP[m.group(1)]})"
        return rename(cond)

    def parse_match(expr_stmt: str) -> Node:
        nonlocal pos
        expr = expr_stmt.split()[1]
        arms = []
        while True:
            tok = tokens[pos]
            if tok.kind == "text":
                assert tok.value.strip() == "", f"non-empty text between match and when: {tok.value!r}"
                pos += 1
                continue
            assert tok.kind == "stmt", tok
            pos += 1
            head = tok.value.split()[0]
            if head == "endmatch":
                return Match(expr, arms)
            assert head == "when", tok
            body, term, _ = parse_block({"when", "endmatch"})
            w = tok.value[len("when") :].strip()
            if w.startswith("Some with"):
                binding = w[len("Some with") :].strip(" ()")
                arms.append((f"Some({binding})", binding, body))
            elif w == "None":
                arms.append(("None", None, body))
            else:
                variant = w.replace("InitHook::", "")
                arms.append((HOOK_MAP[variant], None, body))

    result, _, _ = parse_block(set())
    return result


# ------------------------------------------------------- lowering


CMD_DEFAULTS: set = set()


@dataclass
class Emitter:
    lines: list[str] = field(default_factory=list)
    indent: int = 1

    def emit(self, line: str) -> None:
        self.lines.append("  " * self.indent + line if line else "")


def emit_if(node: If, em: Emitter, declared: dict[str, str], bound: set) -> None:
    # once the windows branch is dropped, the else body is inlined in place (the old output shape)
    arms = [(c, b) for c, b in node.arms if c != "DROP_WINDOWS"]
    if not arms:
        return
    if len(arms) == 1 and arms[0][0] is None:
        walk(arms[0][1], em, declared, bound)
        return
    first = True
    for cond, body in arms:
        if cond is None:
            em.emit("} else {")
        elif first:
            # an in-branch let without decl: the mut declaration is lifted above the if
            for name in scan_assigns([body]):
                if name not in declared:
                    declared[name] = "assign"
                    em.emit(f'let mut {name} : String = ""')
            em.emit(f"if {cond} {{")
            first = False
        else:
            em.emit(f"}} else if {cond} {{")
        em.indent += 1
        walk(body, em, declared, bound)
        em.indent -= 1
    em.emit("}")


def walk(nodes: list[Node], em: Emitter, declared: dict[str, str], bound: set) -> None:
    for node in nodes:
        if isinstance(node, Text):
            em.emit(f'sb.write_string("{moonlit(node.value)}")')
        elif isinstance(node, Expr):
            raw = node.name
            name = raw.strip()
            if name.startswith('"'):
                # a string-literal expression: its content is already escaped, so it is written out as is
                em.emit(f'sb.write_string("{rename(name[1:-1])}")')
            elif name.startswith("cmd"):
                # {{cmd}} (no spaces) = the Some arm binding; {{ cmd }} with spaces / unwrap_or
                # = askama Option interpolation, lowered to cmd_name (None renders the default)
                m = re.match(r"cmd\.unwrap_or\(\"([^\"]*)\"\)$", name)
                if m:
                    em.emit("sb.write_string(cmd_name)")
                    CMD_DEFAULTS.add(m.group(1))
                elif raw == "cmd" and "cmd" in bound:
                    em.emit("sb.write_string(cmd)")
                else:
                    em.emit("sb.write_string(cmd_name)")
                    CMD_DEFAULTS.add("")
            else:
                em.emit(f"sb.write_string({name})")
        elif isinstance(node, Let):
            if node.value is None:
                declared[node.name] = "decl"
                em.emit(f'let mut {node.name} : String = ""')
            elif em.indent == 1 and node.name not in declared:
                declared[node.name] = "let"
                em.emit(f"let {node.name} : String = {node.value}")
            else:
                if node.name not in declared:
                    # an in-branch let without decl: the mut is reserved outside the current block's opening
                    # for the caller to handle, since degrading to an in-place mut declaration here would
                    # break scoping — the assignment is emitted in this branch and the mut comes from the pre-scan (see transpile)
                    declared.setdefault(node.name, "assign")
                em.emit(f"{node.name} = {node.value}")
        elif isinstance(node, If):
            emit_if(node, em, declared, bound)
        elif isinstance(node, Match):
            em.emit(f"match {node.expr} {{")
            em.indent += 1
            for pattern, binding, body in node.arms:
                if not body:
                    em.emit(f"{pattern} => ()")
                    continue
                em.emit(f"{pattern} => {{")
                em.indent += 1
                walk(body, em, declared, bound | ({binding} if binding else set()))
                em.indent -= 1
                em.emit("}")
            em.indent -= 1
            em.emit("}")


def scan_assigns(nodes: list[Node]) -> list[str]:
    out = []
    for node in nodes:
        if isinstance(node, Let) and node.value is not None:
            if node.name not in out:
                out.append(node.name)
    return out


def moonlit(text: str) -> str:
    """Text -> MoonBit string-literal content (escaped)."""
    out = text.replace("\\", "\\\\").replace('"', '\\"')
    out = out.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return out


def transpile(tpl: str, shell: str) -> str:
    global CMD_DEFAULTS
    CMD_DEFAULTS = set()
    nodes = parse(tokenize(tpl))
    em = Emitter()
    declared: dict[str, str] = {}
    walk(nodes, em, declared, set())
    body = "\n".join(em.lines)
    prologue = ""
    if CMD_DEFAULTS:
        default = sorted(CMD_DEFAULTS)[0]
        prologue = (
            "  let cmd_name = match cmd {\n    Some(c) => c\n"
            f'    None => "{default}"\n  }}\n'
        )
    body = prologue + body
    return f'''// Generated by a one-shot transpiler (source: upstream templates/{shell}.txt). Do not edit by hand.
// Renames: zoxide->jumbit, __zoxide_->__jumbit_, _ZO_-> _JB_, z#->j#; the Windows branch is dropped.

///|
/// {shell} template rendering (transpiled from upstream templates/{shell}.txt: zoxide->jumbit, _ZO_-> _JB_; do not edit by hand)
pub fn render_{shell}(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  resolve_symlinks : Bool,
) -> String {{
  let sb = StringBuilder()
{body}
  sb.to_string()
}}
'''


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--src", required=True, help="the upstream templates directory")
    ap.add_argument("--shell", required=True)
    ap.add_argument("--out")
    ap.add_argument("--stdout", action="store_true")
    args = ap.parse_args()

    tpl = open(f"{args.src}/{args.shell}.txt", encoding="utf-8").read()
    code = transpile(tpl, args.shell)
    # parameters a template does not use (elvish ignores resolve_symlinks, tcsh ignores echo, ...):
    # an underscore prefix silences the unused warning; positional callers are unaffected
    for unused in ("resolve_symlinks", "echo"):
        if re.search(r"\b" + unused + r"\b", tpl) is None:
            code = code.replace(unused + " : Bool,", "_" + unused + " : Bool,")
    if args.stdout:
        print(code, end="")
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(code)
        print(f"{args.shell}: {args.out}")


if __name__ == "__main__":
    main()
