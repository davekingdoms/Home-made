"""Controllo dei contrasti WCAG AA sui token di docs/spec/stile.md (sezione 2.1).

Uso: python3 tools/contrasti/contrasti.py docs/spec/stile.md
Legge la tabella dei ruoli e verifica 26 coppie per ciascuna delle sei combinazioni.
Esce con codice 1 se un controllo fallisce (adatto alla CI).
"""
import re
import sys

COMBO = ["Teal scuro", "Teal chiaro", "Dollari scuro", "Dollari chiaro",
         "Mauriziani scuro", "Mauriziani chiaro"]

# (testo o primo piano, sfondo, soglia)
COPPIE = [
    ("onSurface", "surface", 4.5), ("onSurface", "surfaceContainerHighest", 4.5),
    ("onSurfaceVariant", "surface", 4.5), ("onSurfaceVariant", "surfaceContainerHigh", 4.5),
    ("onSurfaceVariant", "surfaceContainerHighest", 4.5),
    ("testoTerziario", "surface", 4.5), ("testoTerziario", "surfaceContainerLow", 4.5),
    ("testoTerziario", "surfaceContainerHigh", 4.5),
    ("onPrimary", "primary", 4.5), ("primary", "surface", 3),
    ("primary", "surfaceContainerLow", 4.5), ("credito", "surfaceContainerLow", 4.5),
    ("debito", "surfaceContainerLow", 4.5),
    ("onPrimaryContainer", "primaryContainer", 4.5), ("onPrimaryContainer", "banda", 4.5),
    ("suPrimarioTenue", "primaryContainer", 4.5), ("suPrimarioTenue", "banda", 4.5),
    ("onSecondaryContainer", "secondaryContainer", 4.5),
    ("onTertiaryContainer", "tertiaryContainer", 4.5),
    ("onError", "error", 4.5), ("onErrorContainer", "errorContainer", 4.5),
    ("avviso", "surface", 3), ("avviso", "surfaceContainerHigh", 3),
    ("outline", "surface", 3), ("outline", "surfaceContainerLow", 3),
    ("error", "surfaceContainerHigh", 4.5),
]


def luminanza(hex_):
    def canale(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * canale(r) + 0.7152 * canale(g) + 0.0722 * canale(b)


def contrasto(a, b):
    la, lb = sorted((luminanza(a), luminanza(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def leggi_ruoli(percorso):
    ruoli = {}
    for riga in open(percorso, encoding="utf-8"):
        m = re.match(r"\|\s*`(\w+)`\s*\|(.+)\|\s*$", riga)
        if not m:
            continue
        valori = [v.strip() for v in m.group(2).split("|")]
        if len(valori) == 6 and all(re.fullmatch(r"#[0-9A-Fa-f]{6}", v) for v in valori):
            ruoli[m.group(1)] = dict(zip(COMBO, valori))
    return ruoli


def main():
    ruoli = leggi_ruoli(sys.argv[1] if len(sys.argv) > 1 else "docs/spec/stile.md")
    falliti, minimo = 0, (99, None)
    for combo in COMBO:
        for a, b, soglia in COPPIE:
            v = contrasto(ruoli[a][combo], ruoli[b][combo])
            if v < minimo[0]:
                minimo = (v, f"{combo}: {a} su {b}")
            if v < soglia:
                falliti += 1
                print(f"NO  {combo}: {a} {ruoli[a][combo]} su {b} {ruoli[b][combo]} = {v:.2f} (minimo {soglia})")
    print(f"Ruoli letti: {len(ruoli)}; controlli: {len(COPPIE) * len(COMBO)}; falliti: {falliti}")
    print(f"Margine più basso: {minimo[0]:.2f} ({minimo[1]})")
    sys.exit(1 if falliti else 0)


if __name__ == "__main__":
    main()
