#!/usr/bin/env python3
"""Szuka slajdów, na których treść nie mieści się w kadrze.

Marp nie zgłasza przepełnienia — po prostu rysuje treść dalej, poza stroną.
Ten skrypt renderuje talie do PNG i sprawdza dwie rzeczy:

  1. WYCIEK — treść wychodzi poza dolną krawędź slajdu.
  2. STOPKA — treść nachodzi na pas z napisem „LFS458 · rozdział N · …".
     Tego pierwszy test nie widzi, bo stopka leży wyżej niż sprawdzany
     przez niego skrawek.

Progi wyznaczone pomiarem na rozdziale 10: slajdy czyste dają 5,0–5,4%
ciemnych pikseli w pasie stopki (to sam napis stopki), slajd z nachodzącym
cytatem — 15,0%. Stąd próg 8%.

    scripts/przyciecie.py build/png/*.png
    scripts/przyciecie.py --renderuj          # wyrenderuj talie i sprawdź
"""
import collections
import glob
import os
import pathlib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

LEWY = 30                       # pomijamy zielone obramowanie klasy `lab`
WYCIEK_WIERSZY, WYCIEK_PROG = 14, 0.004
STOPKA_OD, STOPKA_DO, STOPKA_PRAWA, STOPKA_PROG = 46, 26, 620, 0.08
# Każda talia to osobny Chromium po kilkaset MB. Sześć naraz potrafi
# zagłodzić maszynę, na której stoi jeszcze klaster kind — stąd trójka.
NARAZ = int(os.environ.get("NARAZ", 3))
JASNE_TLO = 120                 # poniżej = slajd na ciemnym tle, bez stopki

ROOT = pathlib.Path(__file__).resolve().parent.parent
PNG = ROOT / "build" / "png"


def jasnosc(p) -> float:
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def zbadaj(sciezka: str) -> list[str]:
    im = Image.open(sciezka).convert("RGB")
    w, h = im.size
    uwagi = []

    dol = [im.getpixel((x, y)) for y in range(h - WYCIEK_WIERSZY, h)
           for x in range(LEWY, w)]
    tlo = collections.Counter(dol).most_common(1)[0][0]
    obce = sum(1 for p in dol if max(abs(a - b) for a, b in zip(p, tlo)) > 24)
    if obce / len(dol) > WYCIEK_PROG:
        uwagi.append(f"treść wychodzi poza dolną krawędź ({obce/len(dol):.1%})")

    pas = [im.getpixel((x, y)) for y in range(h - STOPKA_OD, h - STOPKA_DO)
           for x in range(LEWY, STOPKA_PRAWA)]
    if jasnosc(collections.Counter(pas).most_common(1)[0][0]) >= JASNE_TLO:
        ciemne = sum(1 for p in pas if jasnosc(p) < JASNE_TLO)
        if ciemne / len(pas) > STOPKA_PROG:
            uwagi.append(f"treść nachodzi na stopkę ({ciemne/len(pas):.0%})")
    return uwagi


def renderuj() -> list[str]:
    PNG.mkdir(parents=True, exist_ok=True)
    for stary in PNG.glob("*.png"):
        stary.unlink()
    marp = subprocess.run(["bash", "-c", "command -v marp || echo 'npx marp'"],
                          capture_output=True, text=True).stdout.strip()
    def jedna(md: pathlib.Path) -> None:
        subprocess.run([*marp.split(), "--config-file", ".marprc.yml",
                        "--allow-local-files", "--images", "png",
                        "-o", str(PNG / f"{md.stem}.png"), str(md)],
                       cwd=ROOT, capture_output=True)

    # Każda talia to osobna instancja Chromium, więc po kolei trwa to
    # kilkadziesiąt minut. Puszczamy po kilka naraz — wąskim gardłem jest
    # pamięć, nie procesor, stąd ostrożny limit.
    with ThreadPoolExecutor(max_workers=NARAZ) as pula:
        list(pula.map(jedna, sorted((ROOT / "slides").glob("*.md"))))
    return sorted(glob.glob(str(PNG / "*.png")))


def main() -> int:
    pliki = renderuj() if "--renderuj" in sys.argv else \
        sorted(a for a in sys.argv[1:] if not a.startswith("--"))
    if not pliki:
        print("  brak plików do sprawdzenia", file=sys.stderr)
        return 2
    zle = 0
    for f in pliki:
        for uwaga in zbadaj(f):
            print(f"  {pathlib.Path(f).name}: {uwaga}")
            zle += 1
    print(f"\n  sprawdzono {len(pliki)} slajdów, zastrzeżeń: {zle}")
    return 1 if zle else 0


if __name__ == "__main__":
    raise SystemExit(main())
