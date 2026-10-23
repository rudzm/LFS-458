#!/usr/bin/env python3
"""Buduje `build/html/index.html` — spis rozdziałów dla wersji offline.

Tryb serwera (`make watch`) ma własny spis pod adresem głównym; wyeksportowany
HTML nie ma go wcale, a to do niego prowadzi znacznik „spis rozdziałów"
i klawisz `i`. Ten skrypt uzupełnia brak.

Tytuły czytamy z Markdownu, nie z HTML-a — są tam w jednym, przewidywalnym
miejscu: `# Tytuł` i `## Rozdział N · lab NN` na slajdzie tytułowym.
"""
import html
import re
import sys
from pathlib import Path

SLAJDY = Path("slides")
WYJSCIE = Path("build/html")


def kolejnosc() -> list[str]:
    """Kolejność z `nawigacja.js` — jedno źródło prawdy dla strzałki i spisu.

    Alfabetyczne sortowanie nazw plików dałoby Helma na siódmej pozycji,
    a omawiamy go pod koniec; materiały odwołują się do tej kolejności
    („czego brakowało w module 07" w labie Helma).
    """
    tresc = (SLAJDY / "nawigacja.js").read_text(encoding="utf-8")
    blok = re.search(r"var ROZDZIALY = \[(.*?)\]", tresc, re.S)
    return re.findall(r"'([^']+)'", blok.group(1)) if blok else []


def opis(md: Path) -> tuple[str, str]:
    tresc = md.read_text(encoding="utf-8")
    tytul = re.search(r"^#\s+(.+)$", tresc, re.M)
    podtytul = re.search(r"^##\s+(.+)$", tresc, re.M)
    czysc = lambda s: re.sub(r"[`*]", "", s).strip()
    return (czysc(tytul.group(1)) if tytul else md.stem,
            czysc(podtytul.group(1)) if podtytul else "")


STRONA = """<!doctype html>
<html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LFS458 — spis rozdziałów</title>
<style>
  :root {{ color-scheme: light }}
  body {{ margin:0; padding:48px 24px; background:#f7f9fb; color:#17202a;
         font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }}
  main {{ max-width:720px; margin:0 auto }}
  h1 {{ font-size:28px; margin:0 0 4px }}
  p.wstep {{ color:#5b6b7a; margin:0 0 32px }}
  a.rozdzial {{ display:flex; gap:16px; align-items:baseline; padding:14px 18px;
               margin-bottom:8px; background:#fff; border:1px solid #e3e9ef;
               border-radius:10px; text-decoration:none; color:inherit;
               transition:border-color .15s, transform .15s }}
  a.rozdzial:hover {{ border-color:#27ae60; transform:translateX(3px) }}
  .nr {{ font-variant-numeric:tabular-nums; font-weight:700; color:#27ae60;
        min-width:28px }}
  .tytul {{ font-weight:600 }}
  .meta {{ margin-left:auto; color:#8795a4; font-size:13px; white-space:nowrap }}
  footer {{ margin-top:32px; color:#8795a4; font-size:13px }}
  kbd {{ background:#eef2f6; border:1px solid #d6dee6; border-bottom-width:2px;
        border-radius:4px; padding:1px 5px; font-size:12px }}
</style></head>
<body><main>
<h1>LFS458 — Kubernetes Administration</h1>
<p class="wstep">{ile} prezentacji. Strzałka na ostatnim slajdzie przechodzi
do następnego rozdziału, <kbd>i</kbd> wraca tutaj.</p>
{pozycje}
<footer>Wygenerowane przez <code>scripts/indeks.py</code> razem z <code>make slides-html</code>.</footer>
</main></body></html>
"""


def main() -> int:
    if not WYJSCIE.is_dir():
        print("  brak build/html — uruchom najpierw `make slides-html`", file=sys.stderr)
        return 1

    pozycje = []
    for nazwa in kolejnosc():
        md = SLAJDY / f"{nazwa}.md"
        if not md.exists():
            continue
        strona = WYJSCIE / f"{md.stem}.html"
        if not strona.exists():
            continue
        tytul, meta = opis(md)
        pozycje.append(
            f'<a class="rozdzial" href="{html.escape(strona.name)}">'
            f'<span class="nr">{html.escape(md.stem.split("-")[0])}</span>'
            f'<span class="tytul">{html.escape(tytul)}</span>'
            f'<span class="meta">{html.escape(meta)}</span></a>'
        )

    (WYJSCIE / "index.html").write_text(
        STRONA.format(ile=len(pozycje), pozycje="\n".join(pozycje)), encoding="utf-8")
    print(f"  build/html/index.html — {len(pozycje)} rozdziałów")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
