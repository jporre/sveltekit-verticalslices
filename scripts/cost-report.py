#!/usr/bin/env python3
"""cost-report.py — costo de una sesión de Claude Code a partir de su transcript .jsonl.

Lee el transcript de la sesión (main) y los de sus sub-agentes
(<sesión>/subagents/agent-*.jsonl y <sesión>/subagents/workflows/*/agent-*.jsonl),
deduplica los mensajes assistant por message.id y suma input / output /
cache_read / cache_write. Solo stdlib.

Uso:
  cost-report.py                       # última sesión del proyecto actual (cwd o raíz git)
  cost-report.py <ruta.jsonl>          # una sesión puntual
  cost-report.py --brief               # una sola línea machine-readable (para b7/b9)
  cost-report.py --prices 7.72,38.6,0.772,9.65   # USD por millón: input,output,cache_read,cache_write
  cost-report.py --top 8               # cuántas llamadas grandes listar

Precios default calibrados con una corrida real (2026-09-11, $29.82) bajo la
relación input 1 : output 5 : cache_read 0.1 : cache_write 1.25. Ajustar con --prices.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

DEFAULT_PRICES = (7.72, 38.6, 0.772, 9.65)  # USD / millón de tokens
SKIP_PREFIXES = ("<task-notification>", "<system-reminder>", "<local-command", "<command-name>")


def fmt(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}k"
    return str(n)


def read_jsonl(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def collect(path):
    """Devuelve (llamadas, prompts). llamadas = lista de dicts por message.id único."""
    calls = {}
    order = []
    prompts = []
    for rec in read_jsonl(path):
        t = rec.get("type")
        msg = rec.get("message") or {}
        if t == "assistant":
            mid = msg.get("id") or rec.get("uuid")
            u = msg.get("usage") or {}
            cur = {
                "id": mid,
                "ts": rec.get("timestamp", ""),
                "input": u.get("input_tokens", 0) or 0,
                "output": u.get("output_tokens", 0) or 0,
                "cache_read": u.get("cache_read_input_tokens", 0) or 0,
                "cache_write": u.get("cache_creation_input_tokens", 0) or 0,
                "model": msg.get("model", ""),
            }
            prev = calls.get(mid)
            if prev is None:
                calls[mid] = cur
                order.append(mid)
            elif cur["output"] > prev["output"]:
                calls[mid] = cur
        elif t == "user":
            content = msg.get("content")
            text = None
            if isinstance(content, str):
                text = content
            elif isinstance(content, list) and content and content[0].get("type") == "text":
                text = content[0].get("text", "")
            if text is None:
                continue
            if text.lstrip().startswith(SKIP_PREFIXES):
                continue
            prompts.append({"ts": rec.get("timestamp", ""), "text": text.strip(), "at_call": len(order)})
    return [calls[m] for m in order], prompts


def cost_of(c, p):
    return (c["input"] * p[0] + c["output"] * p[1] + c["cache_read"] * p[2] + c["cache_write"] * p[3]) / 1e6


def totals(calls, p):
    t = {"calls": len(calls), "input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "cost": 0.0}
    for c in calls:
        for k in ("input", "output", "cache_read", "cache_write"):
            t[k] += c[k]
        t["cost"] += cost_of(c, p)
    return t


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(path))


def project_dirs():
    base = os.path.expanduser("~/.claude/projects")
    cands = [os.getcwd()]
    try:
        common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if common:
            cands.append(os.path.dirname(common))
    except Exception:
        pass
    out = []
    for c in cands:
        d = os.path.join(base, slug(c))
        if os.path.isdir(d) and d not in out:
            out.append(d)
    return out


def latest_session(dirs):
    files = []
    for d in dirs:
        files += glob.glob(os.path.join(d, "*.jsonl"))
    if not files:
        return None
    return max(files, key=os.path.getmtime)


def subagent_files(session_jsonl):
    sdir = session_jsonl[:-len(".jsonl")]
    files = glob.glob(os.path.join(sdir, "subagents", "agent-*.jsonl"))
    files += glob.glob(os.path.join(sdir, "subagents", "workflows", "*", "agent-*.jsonl"))
    return sorted(files)


def label_for(agent_jsonl):
    meta = agent_jsonl[:-len(".jsonl")] + ".meta.json"
    name = os.path.basename(os.path.dirname(agent_jsonl))
    kind = "agent"
    if name.startswith("wf_"):
        kind = name
    try:
        with open(meta, encoding="utf-8") as fh:
            m = json.load(fh)
        desc = m.get("description") or m.get("agentType") or ""
        phase = m.get("workflowPhase")
        return f"{kind}:{phase + ':' if phase else ''}{desc}"[:48]
    except Exception:
        return f"{kind}:{os.path.basename(agent_jsonl)[:20]}"


def row(label, t):
    return f"{label:<50} {t['calls']:>5} {fmt(t['input']):>8} {fmt(t['output']):>8} {fmt(t['cache_read']):>10} {fmt(t['cache_write']):>11}  ${t['cost']:>7.2f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("session", nargs="?", help="ruta al .jsonl de la sesión (default: la más reciente del proyecto)")
    ap.add_argument("--prices", help="USD/M: input,output,cache_read,cache_write")
    ap.add_argument("--brief", action="store_true", help="una línea machine-readable")
    ap.add_argument("--top", type=int, default=5, help="llamadas más caras a listar")
    a = ap.parse_args()

    prices = DEFAULT_PRICES
    if a.prices:
        prices = tuple(float(x) for x in a.prices.split(","))
        if len(prices) != 4:
            sys.exit("--prices espera 4 valores: input,output,cache_read,cache_write")

    session = a.session or latest_session(project_dirs())
    if not session or not os.path.isfile(session):
        sys.exit("cost-report: no encontré transcript de sesión (pasa la ruta .jsonl)")

    main_calls, prompts = collect(session)
    sources = [("main", main_calls)]
    for f in subagent_files(session):
        calls, _ = collect(f)
        if calls:
            sources.append((label_for(f), calls))

    all_calls = [c for _, calls in sources for c in calls]
    tot = totals(all_calls, prices)
    sid = os.path.basename(session)[:-len(".jsonl")]

    if a.brief:
        print(
            f"COST session={sid[:8]} calls={tot['calls']} prompts={len(prompts)} "
            f"output={fmt(tot['output'])} cache_read={fmt(tot['cache_read'])} "
            f"cache_write={fmt(tot['cache_write'])} subagents={len(sources)-1} usd={tot['cost']:.2f}"
        )
        return

    print(f"Sesión {sid}  ({session})")
    print(f"Precios USD/M  input={prices[0]} output={prices[1]} cache_read={prices[2]} cache_write={prices[3]}\n")
    hdr = f"{'fuente':<50} {'calls':>5} {'input':>8} {'output':>8} {'cache_rd':>10} {'cache_wr':>11}  {'USD':>8}"
    print(hdr)
    print("-" * len(hdr))
    for label, calls in sources:
        print(row(label, totals(calls, prices)))
    print("-" * len(hdr))
    print(row("TOTAL", tot))

    if prompts:
        print(f"\nPor prompt del usuario (solo main, {len(prompts)} prompts)")
        bounds = [p["at_call"] for p in prompts] + [len(main_calls)]
        for i, p in enumerate(prompts):
            seg = main_calls[bounds[i]:bounds[i + 1]]
            if not seg:
                continue
            t = totals(seg, prices)
            ctx = max(c["input"] + c["cache_read"] + c["cache_write"] for c in seg)
            when = p["ts"][11:16] if len(p["ts"]) >= 16 else ""
            text = re.sub(r"\s+", " ", p["text"])[:60]
            print(f"  {i+1:>2} {when} calls={t['calls']:<3} out={fmt(t['output']):>6} ctx_max={fmt(ctx):>6} ${t['cost']:>6.2f}  {text}")

    if a.top > 0 and main_calls:
        print(f"\nTop {a.top} llamadas de main por contexto (input+cache)")
        big = sorted(main_calls, key=lambda c: c["input"] + c["cache_read"] + c["cache_write"], reverse=True)[: a.top]
        for c in big:
            ctx = c["input"] + c["cache_read"] + c["cache_write"]
            print(f"  {c['ts'][11:19]}  ctx={fmt(ctx):>7}  out={fmt(c['output']):>6}  ${cost_of(c, prices):.2f}")


if __name__ == "__main__":
    main()
