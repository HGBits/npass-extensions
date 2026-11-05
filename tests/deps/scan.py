#!/usr/bin/env python3
"""Extrai dependencias declaradas/usadas para tests/deps.bats.

Subcomandos (saida: uma linha por item, campos separados por TAB):
  py-imports    modulos Python nao-stdlib importados (por AST)
  py-commands   binarios com literal em subprocess.*/shutil.which (por AST)
  cargo-deps    nome<TAB>versao para cada dep direta de passkey/Cargo.toml
  lock-bad      pacotes do Cargo.lock com source nao-crates.io ou sem checksum
  lock-names    nomes de todos os pacotes de registry do Cargo.lock
  lock-missing  deps diretas do Cargo.toml ausentes do Cargo.lock
  registry      (rede) crates.io: existe, checksum, yanked; PyPI: existe
Limite: py-commands so ve literais no primeiro elemento da lista passada.
"""
import ast, json, pathlib, re, sys, tomllib, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CRATES = "registry+https://github.com/rust-lang/crates.io-index"


def py_files():
    out = []
    for p in sorted(ROOT.iterdir()):
        if p.is_file():
            first = p.read_bytes()[:128].split(b"\n")[0]
            if first.startswith(b"#!") and b"python" in first:
                out.append(p)
    out += sorted((ROOT / "tests").glob("*.py"))
    return [p for p in out if p.name != "scan.py"]


def py_imports():
    found = set()
    for f in py_files():
        for n in ast.walk(ast.parse(f.read_text())):
            mods = []
            if isinstance(n, ast.Import):
                mods = [a.name for a in n.names]
            elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
                mods = [n.module]
            for m in mods:
                top = m.split(".")[0]
                if top not in sys.stdlib_module_names:
                    found.add(top)
    return sorted(found)


def py_commands():
    found = set()
    for f in py_files():
        for n in ast.walk(ast.parse(f.read_text())):
            if not isinstance(n, ast.Call) or not n.args:
                continue
            fn = n.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
            a = n.args[0]
            if name in ("run", "Popen", "check_output", "check_call", "call") and isinstance(a, (ast.List, ast.Tuple)):
                if a.elts and isinstance(a.elts[0], ast.Constant) and isinstance(a.elts[0].value, str):
                    found.add(a.elts[0].value)
            elif name == "which" and isinstance(a, ast.Constant) and isinstance(a.value, str):
                found.add(a.value)
    return sorted(found)


def manifest():
    return tomllib.loads((ROOT / "passkey" / "Cargo.toml").read_text())


def direct_deps():
    t, deps = manifest(), {}
    tables = [t.get(k, {}) for k in ("dependencies", "dev-dependencies", "build-dependencies")]
    for tgt in t.get("target", {}).values():
        tables += [tgt.get(k, {}) for k in ("dependencies", "dev-dependencies", "build-dependencies")]
    for tb in tables:
        for name, spec in tb.items():
            real = spec.get("package", name) if isinstance(spec, dict) else name
            ver = spec if isinstance(spec, str) else spec.get("version", "")
            deps[real] = ver
    return deps


def lock_pkgs():
    return tomllib.loads((ROOT / "passkey" / "Cargo.lock").read_text()).get("package", [])


def main(cmd):
    if cmd == "py-imports":
        print("\n".join(py_imports()))
    elif cmd == "py-commands":
        print("\n".join(py_commands()))
    elif cmd == "cargo-deps":
        for n, v in sorted(direct_deps().items()):
            print(f"{n}\t{v}")
    elif cmd == "lock-bad":
        for p in lock_pkgs():
            src, ck = p.get("source"), p.get("checksum")
            if src is None:
                continue  # crate local (o proprio daemon)
            if src != CRATES:
                print(f"{p['name']}\tsource fora do crates.io: {src}")
            elif not ck:
                print(f"{p['name']}\tsem checksum")
    elif cmd == "lock-names":
        print("\n".join(sorted({p["name"] for p in lock_pkgs() if p.get("source")})))
    elif cmd == "lock-missing":
        names = {p["name"] for p in lock_pkgs()}
        for n in sorted(direct_deps()):
            if n not in names:
                print(n)
    elif cmd == "registry":
        registry()
    else:
        sys.exit(f"uso: scan.py {{py-imports|py-commands|cargo-deps|lock-bad|lock-names|lock-missing|registry}}")


def idx_path(n):
    n = n.lower()
    return "1/" + n if len(n) == 1 else "2/" + n if len(n) == 2 else f"3/{n[0]}/{n}" if len(n) == 3 else f"{n[:2]}/{n[2:4]}/{n}"


def http(url):
    req = urllib.request.Request(url, headers={"User-Agent": "npass-deps-test"})
    return urllib.request.urlopen(req, timeout=25).read().decode()


def registry():
    for p in lock_pkgs():
        if not p.get("source"):
            continue
        n, v = p["name"], p["version"]
        try:
            rows = [json.loads(l) for l in http("https://index.crates.io/" + idx_path(n)).splitlines()]
        except urllib.error.HTTPError as e:
            print(f"{n}\tNAO EXISTE no crates.io (HTTP {e.code})" if e.code == 404 else f"{n}\tHTTP {e.code}")
            continue
        row = next((r for r in rows if r["vers"] == v), None)
        if row is None:
            print(f"{n}\tversao {v} NAO EXISTE")
        elif row["cksum"] != p.get("checksum"):
            print(f"{n}\tchecksum do lock diverge do registro ({v})")
        elif row.get("yanked"):
            print(f"{n}\tversao {v} esta YANKED; rode `cargo update -p {n}`")
    for m in py_imports():
        try:
            http(f"https://pypi.org/pypi/{m}/json")
        except urllib.error.HTTPError as e:
            print(f"{m}\tNAO EXISTE no PyPI (HTTP {e.code})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "")
