#!/usr/bin/env python3
"""validate-spec.py — ensayo y certificación de una SPEC de b11-spec-exec. Solo stdlib.

Uso:
  validate-spec.py SPEC.md            ensayo: clona el REPO de la spec en un tmp, aplica copias y
                                      ediciones, corre la aceptación y compara el estado git → SPEC OK
  validate-spec.py SPEC.md --check    certificación tras el ejecutor: repite el ensayo en un tmp y
                                      compara byte a byte (y bit de ejecución) cada archivo tocado
                                      contra el repo real; aceptación y estado git sobre el real → CHECK OK
  validate-spec.py SPEC.md --repo R   usa R en vez de la línea REPO: (pruebas sobre un clon)
  validate-spec.py SPEC.md --keep     conserva el tmp e imprime su ruta

Marcadores que lee (ver references/spec-template.md):
  REPO: /ruta/absoluta
  COPIAR: /origen/absoluto -> destino/relativo [+x]
  ARCHIVO: ruta/relativa
  BUSCAR:  / REEMPLAZAR:   cada uno seguido de un bloque cercado (``` o más acentos graves)
  ## … Aceptación          primer bloque cercado: un comando por línea, todos deben salir 0 (cwd = repo)
  ## … Estado git …        primer bloque cercado: salida esperada de `git status --porcelain`
Exit 0 si todo pasa, 1 si algo falla, 2 si la spec no parsea.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

FENCE = re.compile(r"^(`{3,})")


def die(msg):
    print(f"SPEC INVÁLIDA: {msg}")
    sys.exit(2)


def read_block(lines, i):
    """(texto, índice tras la valla de cierre) del bloque cercado que empieza en la línea i o después."""
    j = i
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    m = FENCE.match(lines[j]) if j < len(lines) else None
    if not m:
        die(f"línea {i + 1}: se esperaba un bloque cercado")
    ticks = m.group(1)
    k = j + 1
    block = []
    while k < len(lines) and lines[k] != ticks:
        block.append(lines[k])
        k += 1
    if k >= len(lines):
        die(f"línea {j + 1}: bloque cercado sin cerrar")
    return "\n".join(block), k + 1


def parse(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    spec = {"repo": None, "copies": [], "edits": [], "accept": None, "status": None}
    cur_file = None
    pending = None
    section = None
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if (m := re.match(r"^REPO:\s*(\S+)$", s)) and spec["repo"] is None:
            spec["repo"] = os.path.expanduser(m.group(1))
        elif m := re.match(r"^COPIAR:\s*(\S+)\s*->\s*(\S+)(\s+\+x)?$", s):
            spec["copies"].append((os.path.expanduser(m.group(1)), m.group(2), bool(m.group(3))))
        elif m := re.match(r"^ARCHIVO:\s*(\S+)$", s):
            cur_file = m.group(1)
        elif s.startswith("## "):
            low = s.lower()
            section = "accept" if "aceptaci" in low else "status" if "estado git" in low else None
        elif s == "BUSCAR:":
            if cur_file is None:
                die(f"línea {i + 1}: BUSCAR sin ARCHIVO previo")
            pending, i = read_block(lines, i + 1)
            continue
        elif s == "REEMPLAZAR:":
            if pending is None:
                die(f"línea {i + 1}: REEMPLAZAR sin BUSCAR")
            new, i = read_block(lines, i + 1)
            spec["edits"].append((cur_file, pending, new))
            pending = None
            continue
        elif section and FENCE.match(s) and spec[section] is None:
            block, i = read_block(lines, i)
            rows = block.split("\n")
            if section == "accept":
                rows = [r for r in rows if r.strip() and not r.lstrip().startswith("#")]
            spec[section] = rows
            continue
        i += 1
    if not spec["repo"]:
        die("falta la línea REPO:")
    if pending is not None:
        die("BUSCAR sin REEMPLAZAR al final")
    if not spec["copies"] and not spec["edits"]:
        die("sin COPIAR ni ediciones")
    return spec


def sh(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def fresh_clone(repo):
    tmp = tempfile.mkdtemp(prefix="b11-")
    r = sh(["git", "clone", "-q", repo, tmp], None)
    if r.returncode != 0:
        die(f"git clone falló: {r.stderr.strip()}")
    return tmp


def chmod_x(path):
    os.chmod(path, os.stat(path).st_mode | 0o111)


def apply(spec, root, log):
    ok = True
    touched = []
    for src, dst, execbit in spec["copies"]:
        d = os.path.join(root, dst)
        if not os.path.exists(src):
            log(f"FAIL copia  {dst}: no existe el origen {src}")
            ok = False
            continue
        os.makedirs(os.path.dirname(d) or root, exist_ok=True)
        if os.path.isdir(src):
            shutil.copytree(src, d, dirs_exist_ok=True)
            if execbit:
                for r, _, fs in os.walk(d):
                    for f in fs:
                        chmod_x(os.path.join(r, f))
        else:
            shutil.copy2(src, d)
            if execbit:
                chmod_x(d)
        touched.append(dst)
        log(f"ok   copia  {dst}")
    for f, old, new in spec["edits"]:
        p = os.path.join(root, f)
        if not os.path.isfile(p):
            log(f"FAIL edita  {f}: no existe")
            ok = False
            continue
        s = open(p, encoding="utf-8").read()
        n = s.count(old)
        if n != 1:
            head = (old.strip().splitlines() or [""])[0][:60]
            log(f"FAIL edita  {f}: {n} ocurrencias de BUSCAR «{head}»")
            ok = False
            continue
        open(p, "w", encoding="utf-8").write(s.replace(old, new))
        touched.append(f)
        log(f"ok   edita  {f}")
    return ok, touched


def run_accept(spec, root, log):
    if not spec["accept"]:
        log("skip aceptación (sin sección)")
        return True
    ok = True
    for cmd in spec["accept"]:
        r = sh(["bash", "-c", cmd], root)
        if r.returncode != 0:
            ok = False
            log(f"FAIL acepta (exit {r.returncode}): {cmd}\n     {(r.stdout + r.stderr).strip()[:300]}")
        else:
            log(f"ok   acepta {cmd[:72]}")
    return ok


def norm(lines):
    return sorted(re.sub(r"\s+", " ", l.strip()) for l in lines if l.strip())


def check_status(spec, root, log):
    if spec["status"] is None:
        log("skip estado git (sin sección)")
        return True
    got = norm(sh(["git", "status", "--porcelain"], root).stdout.splitlines())
    exp = norm(spec["status"])
    if got == exp:
        log(f"ok   estado git: {len(got)} entradas")
        return True
    log("FAIL estado git\n     esperado: " + " | ".join(exp) + "\n     obtenido: " + " | ".join(got))
    return False


def files_under(root, rel):
    p = os.path.join(root, rel)
    if os.path.isfile(p):
        return [rel]
    return [os.path.relpath(os.path.join(r, f), root) for r, _, fs in os.walk(p) for f in fs]


def compare(touched, tmp, repo, log):
    ok = True
    for rel in touched:
        for rf in files_under(tmp, rel):
            a, b = os.path.join(tmp, rf), os.path.join(repo, rf)
            if not os.path.isfile(b):
                log(f"FAIL falta en el repo: {rf}")
                ok = False
            elif open(a, "rb").read() != open(b, "rb").read():
                log(f"FAIL difiere: {rf}")
                ok = False
            elif (os.stat(a).st_mode & 0o111) != (os.stat(b).st_mode & 0o111):
                log(f"FAIL bit de ejecución difiere: {rf}")
                ok = False
            else:
                log(f"ok   igual  {rf}")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--check", action="store_true", help="certificar el repo real tras el ejecutor")
    ap.add_argument("--repo", help="usar esta ruta en vez de la línea REPO: de la spec")
    ap.add_argument("--keep", action="store_true", help="conservar el clon temporal")
    a = ap.parse_args()
    spec = parse(a.spec)
    repo = os.path.abspath(a.repo or spec["repo"])
    # rev-parse y no .git/: en worktrees (caso normal del pipeline) .git es un gitfile.
    if not os.path.isdir(repo) or sh(["git", "rev-parse", "--is-inside-work-tree"], repo).stdout.strip() != "true":
        die(f"REPO no es un repo git: {repo}")
    log = print
    tmp = fresh_clone(repo)
    try:
        ok, touched = apply(spec, tmp, log)
        if a.check:
            ok = compare(touched, tmp, repo, log) and ok
            ok = run_accept(spec, repo, log) and ok
            ok = check_status(spec, repo, log) and ok
            verdict = "CHECK"
        else:
            if ok:
                ok = run_accept(spec, tmp, log) and ok
                ok = check_status(spec, tmp, log) and ok
            verdict = "SPEC"
        print(f"{verdict} {'OK' if ok else 'FALLA'}: {len(spec['copies'])} copias, {len(spec['edits'])} ediciones, "
              f"{len(spec['accept'] or [])} comandos de aceptación")
    finally:
        if a.keep:
            print(f"tmp conservado: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
