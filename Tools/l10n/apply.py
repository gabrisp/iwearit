#!/usr/bin/env python3
"""Reescribe los textos a claves y genera los catálogos (.xcstrings)."""
import json, re, sys, importlib.util, collections
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DRY = "--dry" in sys.argv

# Las traducciones, por el texto en español: sobreviven a volver a extraer.
en_of = json.load(open(HERE / "translations.json"))
items = json.load(open(HERE / "inventory.json"))

def camel(words):
    words = [w for w in re.findall(r"[A-Za-z0-9]+", words)][:5]
    if not words: return "text"
    return words[0].lower() + "".join(w[:1].upper() + w[1:].lower() for w in words[1:])

def scope_of(path):
    parts = Path(path).parts
    if parts[0] == "WardrobeKit":
        return parts[2].lower(), parts[2]          # (prefijo, target del paquete)
    if "Features" in parts:
        return parts[parts.index("Features") + 1].lower(), None
    return "app", None

# Textos que salen en 3 o más ficheros: una clave común.
files_per_text = collections.defaultdict(set)
for it in items:
    if en_of.get(it["text"]): files_per_text[it["text"]].add(it["file"])

keys = {}          # (bundle, text, file) -> key
used = collections.defaultdict(set)   # bundle -> keys
catalog = collections.defaultdict(dict)  # bundle -> key -> (en, es)

def key_for(it):
    text, en = it["text"], en_of[it["text"]]
    prefix, target = scope_of(it["file"])
    bundle = target or "app"
    shared = len(files_per_text[text]) >= 3
    ident = (bundle, text, "" if shared else it["file"])
    if ident in keys: return keys[ident], bundle
    base = ("common" if shared else prefix + "." + camel(Path(it["file"]).stem)) + "." + camel(re.sub(r"\{\d+\}", " ", en))
    key, n = base, 2
    while key in used[bundle] and catalog[bundle].get(key, (None, None))[1] != text:
        key = f"{base}{n}"; n += 1
    used[bundle].add(key); keys[ident] = key
    catalog[bundle][key] = (en, text)
    return key, bundle

def swift_escape_default(en, exprs):
    # Primero el texto en inglés escapado, y **después** las expresiones tal
    # cual: escapar las comillas de una expresión la rompía.
    out = en.replace('"', '\\"')
    for i, e in enumerate(exprs):
        out = out.replace("{%d}" % i, "\\(String(describing: %s))" % e.strip())
    return out

report = collections.defaultdict(list)
by_file = collections.defaultdict(list)
for it in items:
    en = en_of.get(it["text"])
    if not en: continue
    by_file[it["file"]].append(it)

changed = 0
for file, its in by_file.items():
    path = ROOT / file
    src = path.read_text()
    for it in sorted(its, key=lambda x: -x["start"]):
        line_start = src.rfind("\n", 0, it["start"]) + 1
        line = src[line_start:src.find("\n", it["end"])]
        before = src[line_start:it["start"]]
        after = src[it["end"]:src.find("\n", it["end"])]
        if re.search(r"^\s*case\b", before) and re.match(r"\s*[,:]", after) and not re.search(r"(case\s+\.|case\s+let)", before):
            report["patrón case"].append(f"{file}:{it['line']} {it['text']}"); continue
        if re.search(r"(==|!=)\s*$", before) or re.match(r"\s*(==|!=)", after):
            report["comparación"].append(f"{file}:{it['line']} {it['text']}"); continue
        if it["multiline"]:
            report["multilínea"].append(f"{file}:{it['line']} {it['text'][:40]}"); continue
        if re.search(r"\*\*|\]\(", it["text"]):
            report["markdown"].append(f"{file}:{it['line']} {it['text'][:40]}")
        key, bundle = key_for(it)
        default = swift_escape_default(en_of[it["text"]], it["exprs"])
        bundle_arg = ", bundle: .module" if bundle != "app" else ""
        new = f'String(localized: "{key}", defaultValue: "{default}"{bundle_arg})'
        src = src[:it["start"]] + new + src[it["end"]:]
        changed += 1
    if not DRY: path.write_text(src)

def unescape(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")

def fmt(s):
    i = 0
    def rep(m): return "%" + str(int(m.group(1)) + 1) + "$@"
    return re.sub(r"\{(\d+)\}", rep, unescape(s))

for bundle, entries in catalog.items():
    doc = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    for key in sorted(entries):
        en, es = entries[key]
        doc["strings"][key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": fmt(en)}},
                "es": {"stringUnit": {"state": "translated", "value": fmt(es)}},
            },
        }
    if bundle == "app":
        out = ROOT / "iWearIt" / "Localizable.xcstrings"
    else:
        out = ROOT / "WardrobeKit" / "Sources" / bundle / "Resources" / "Localizable.xcstrings"
    if not DRY:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=False))
    print(f"{bundle}: {len(entries)} claves → {out.relative_to(ROOT)}")

print("reemplazos:", changed)
for kind, lst in report.items():
    print(f"\n[{kind}] {len(lst)}")
    for l in lst: print("  ", l)
