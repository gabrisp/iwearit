#!/usr/bin/env python3
"""Inventario de textos visibles en el Swift de la app y del paquete.

Recorre cada fichero con un tokenizador mínimo (comentarios, cadenas con
interpolación anidada, cadenas multilínea) y se queda con los literales que
parecen texto para el usuario. Escribe `inventory.json` con, por literal:
fichero, desplazamiento, texto con las interpolaciones como {0}, {1}… y la
lista de expresiones interpoladas.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "iWearIt", ROOT / "WardrobeKit" / "Sources"]

def tokenize(src):
    """Devuelve literales: (start, end, parts, exprs, multiline) saltando comentarios."""
    i, n = 0, len(src)
    out = []
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i): depth += 1; i += 2
                elif src.startswith("*/", i): depth -= 1; i += 2
                else: i += 1
            continue
        if src.startswith('#"', i):  # raw string: skip
            j = src.find('"#', i + 2); i = n if j < 0 else j + 2; continue
        if c == '"':
            lit = read_string(src, i)
            if lit is None: i += 1; continue
            out.append(lit); i = lit[1]; continue
        i += 1
    return out

def read_string(src, i):
    multiline = src.startswith('"""', i)
    j = i + (3 if multiline else 1)
    n = len(src)
    parts, exprs, buf = [], [], []
    while j < n:
        if multiline and src.startswith('"""', j):
            parts.append("".join(buf)); return (i, j + 3, parts, exprs, True)
        ch = src[j]
        if not multiline and ch == '"':
            parts.append("".join(buf)); return (i, j + 1, parts, exprs, False)
        if not multiline and ch == "\n":
            return None
        if ch == "\\" and j + 1 < n and src[j + 1] == "(":
            k, depth = j + 2, 1
            start = k
            while k < n and depth:
                if src[k] == '"':
                    inner = read_string(src, k)
                    if inner is None: return None
                    k = inner[1]; continue
                if src[k] == "(": depth += 1
                elif src[k] == ")": depth -= 1
                k += 1
            parts.append("".join(buf)); buf = []
            exprs.append(src[start:k - 1]); j = k; continue
        if ch == "\\":
            buf.append(src[j:j + 2]); j += 2; continue
        buf.append(ch); j += 1
    return None

SPANISH = re.compile(r"[áéíóúñÁÉÍÓÚÑ¿¡]|\b(de|la|el|los|las|tu|tus|que|con|sin|para|una|un|por|más|y|en|no|se|lo|al|del|ya|te|mi|es|está|hay|todo|nada|esta|este)\b", re.I)
WORDY = re.compile(r"[A-Za-zÁÉÍÓÚáéíóúñÑ]{2,}")

EXCLUDE_CONTEXT = re.compile(
    r"(DiagnosticsLog\.record|Logger\(|\.notice\(|\.error\(|\.debug\(|\.info\(|print\(|fatalError\(|"
    r"assertionFailure\(|preconditionFailure\(|systemName:|Image\(\s*$|forKey|UserDefaults|@AppStorage\(|"
    r"URL\(string|appending\(path|NSPredicate\(format|\.custom\(|named:|Notification\.Name|"
    r"setValue\(|forHTTPHeaderField|UTType\(|subsystem:|category:|#Predicate|\.log\(|os_log|Bundle\.main|"
    r"environment\[|arguments\.contains|firstIndex\(of:|record\(\s*$|decode\(|encode\(|keyPath|"
    r"CodingKey|identifier:|symbol:\s*$|symbolName|\bsymbol\b\s*[:=]|contentType|mimeType)\s*$"
)

def context_before(src, start, width=90):
    line_start = src.rfind("\n", 0, start) + 1
    return src[max(line_start, start - width):start]

EXCLUDE_FILES = {
    # Tablas para reconocer marcas y leer páginas de producto: nombres propios
    # y palabras que se buscan en el texto de la foto, no texto de la app.
    "BrandRecognizer.swift", "RetailGroups.swift", "ProductPageReader.swift",
    # Registro del pipeline.
    "GarmentPipeline.swift",
    # Vocabulario: son datos guardados; se traducen al enseñarlos. Ver
    # `GarmentVocabulary.display`.
    "GarmentVocabulary.swift",
}
LOG_CALLS = {"record", "notice", "error", "debug", "info", "warning", "fault", "log", "print",
             "fatalError", "assertionFailure", "preconditionFailure", "Logger", "os_log",
             "request", "setValue", "UTType", "URL", "NSPredicate", "appending", "custom"}

def inside_call(src, start, names, reach=900):
    """Si el literal está dentro de una llamada a alguna de `names`."""
    depth, i, stop = 0, start - 1, max(0, start - reach)
    while i > stop:
        ch = src[i]
        if ch in ")]": depth += 1
        elif ch in "([":
            if depth == 0:
                if ch == "(":
                    j = i - 1
                    while j >= 0 and (src[j].isalnum() or src[j] in "_"): j -= 1
                    if src[j + 1:i] in names: return True
            else:
                depth -= 1
        elif ch == "{" and depth == 0:
            return False
        i -= 1
    return False

def is_ui(text, before, src, start):
    t = text.strip()
    if len(t) < 2 or not WORDY.search(t): return False
    if inside_call(src, start, LOG_CALLS): return False
    if EXCLUDE_CONTEXT.search(before): return False
    if re.search(r"(DiagnosticsLog\.record|Logger|record)\(\s*\"[A-ZÁÉÍÓÚ ]+\"\s*,\s*$", before): return False
    line_start = src.rfind("\n", 0, start) + 1
    line = src[line_start:src.find("\n", start)]
    if re.search(r"DiagnosticsLog\.record|Logger\(|\.notice\(|print\(|fatalError|systemName|forHTTPHeaderField|UserDefaults|AppStorage|URL\(string|appending\(path|\.custom\(\"", line): return False
    if re.match(r"^\s*case\s+\w+\s*=\s*\"", line): return False  # raw values
    # SF Symbols / identificadores / claves
    if re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", t): return False
    if re.fullmatch(r"[A-Za-z0-9_\-\.:/#%@+]+", t) and not SPANISH.search(t) and not re.search(r"[A-Z][a-z]", t): return False
    if re.fullmatch(r"#[0-9A-Fa-f]{6}", t): return False
    if t.startswith("http") or t.startswith("com.") or t.startswith("$"): return False
    has_space = " " in t
    ui_call = re.search(r"(Text|Label|Button|Pill|Toggle|TextField|Section|navigationTitle|alert|WKSection|WKPrimaryButton|WKSecondaryButton)\(\s*$|(title|label|subtitle|placeholder|message|caption|detail|primaryTitle):\s*$", before)
    if ui_call and re.fullmatch(r"[a-záéíóúñ…]+", t): return True
    if not has_space and not SPANISH.search(t) and not re.match(r"^[A-ZÁÉÍÓÚ][a-záéíóúñ]+$", t): return False
    return True

items = []
for base in SOURCES:
    for path in sorted(base.rglob("*.swift")):
        if path.name in EXCLUDE_FILES: continue
        src = path.read_text()
        for (start, end, parts, exprs, multiline) in tokenize(src):
            template = ""
            for k, p in enumerate(parts):
                template += p
                if k < len(exprs): template += "{%d}" % k
            before = context_before(src, start)
            if not is_ui(re.sub(r"\{\d+\}", " x ", template), before, src, start): continue
            line_no = src.count("\n", 0, start) + 1
            items.append({
                "file": str(path.relative_to(ROOT)), "line": line_no, "start": start, "end": end,
                "text": template, "exprs": exprs, "multiline": multiline, "before": before.strip()[-60:],
            })
out = Path(__file__).with_name("inventory.json")
out.write_text(json.dumps(items, ensure_ascii=False, indent=1))
files = {}
for it in items: files[it["file"]] = files.get(it["file"], 0) + 1
print("literales:", len(items), "· únicos:", len({i["text"] for i in items}), "· ficheros:", len(files))
for f, c in sorted(files.items(), key=lambda x: -x[1])[:25]: print(f"  {c:4d}  {f}")
