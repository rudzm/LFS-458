#!/usr/bin/env python3
"""Owija bloki slajdów w `<div data-marpit-fragment>`, żeby pojawiały się po kolei.

Marp sam fragmentuje tylko listy pisane gwiazdką. Akapity, tabele, cytaty
i bloki kodu trzeba oznaczyć jawnie — i właśnie to robi ten skrypt.

    scripts/fragmenty.py              # oznacz wszystkie talie
    scripts/fragmenty.py --cofnij     # zdejmij oznaczenia
    scripts/fragmenty.py slides/01-basics.md

Czego NIE rusza:
  * slajdów tytułowych i sekcyjnych (`_class: tytul`, `_class: sekcja`) —
    te mają pojawiać się w całości,
  * nagłówka `#` slajdu — tytuł widać od pierwszej chwili,
  * list — te fragmentuje sam Marp, punkt po punkcie, dzięki gwiazdce;
    zapakowanie ich dodatkowo w `div` rozjechałoby numerację kroków,
  * znaczników `<div class="kolumny">` — opakowujemy to, co w środku.
"""
import re
import sys
from pathlib import Path

OTWARCIE = "<div data-marpit-fragment>"
ZAMKNIECIE = "</div>"
BEZ_FRAGMENTOW = ("_class: tytul", "_class: sekcja")
# Slajd z tym znacznikiem skrypt zostawia dokładnie takim, jaki jest — ani
# nie dokłada opakowań, ani ich nie zdejmuje. Przydaje się tam, gdzie podział
# na kroki ma iść inaczej niż „blok po bloku": na slajdzie porównawczym
# chcemy odsłaniać całą kolumnę naraz, a nie punkt po punkcie.
RECZNIE = "<!-- fragmenty: ręcznie -->"


def bloki(linie: list[str]):
    """Dzieli slajd na bloki rozdzielone pustą linią, szanując ogrodzenia kodu."""
    biezacy: list[str] = []
    w_kodzie = False
    for l in linie:
        if l.lstrip().startswith("```"):
            w_kodzie = not w_kodzie
            biezacy.append(l)
            continue
        if not w_kodzie and not l.strip():
            if biezacy:
                yield biezacy
                biezacy = []
            continue
        biezacy.append(l)
    if biezacy:
        yield biezacy


def do_owiniecia(blok: list[str]) -> bool:
    pierwsza = blok[0].lstrip()
    # `#` to tytuł slajdu, a `##` podtytuł talii — widoczne od pierwszej chwili.
    # Ale `###` i głębsze to nagłówki *w treści*, najczęściej nad kolumną:
    # bez opakowania wisiałyby nad pustką, zanim pojawi się to, co opisują.
    if pierwsza.startswith("#") and not pierwsza.startswith("###"):
        return False
    if pierwsza.startswith(("<", "-->")):  # surowy HTML: kolumny, komentarze
        return False
    if re.match(r"^[*+-]\s+\S", pierwsza):  # listy fragmentuje sam Marp
        return False
    return True


def oznacz_slajd(tekst: str) -> str:
    if RECZNIE in tekst or any(z in tekst for z in BEZ_FRAGMENTOW):
        return tekst.strip("\n")
    wynik: list[str] = []
    for blok in bloki(tekst.split("\n")):
        if do_owiniecia(blok):
            wynik += [OTWARCIE, ""] + blok + ["", ZAMKNIECIE, ""]
        else:
            wynik += blok + [""]
    return "\n".join(wynik).strip("\n")


def podziel_na_slajdy(tresc: str) -> tuple[str, list[str]]:
    """Oddziela front matter od slajdów rozdzielonych linią `---`."""
    linie = tresc.split("\n")
    naglowek: list[str] = []
    if linie and linie[0].strip() == "---":
        koniec = next(i for i in range(1, len(linie)) if linie[i].strip() == "---")
        naglowek = linie[: koniec + 1]
        linie = linie[koniec + 1 :]

    slajdy, biezacy, w_kodzie = [], [], False
    for l in linie:
        if l.lstrip().startswith("```"):
            w_kodzie = not w_kodzie
        if not w_kodzie and l.strip() == "---":
            slajdy.append("\n".join(biezacy))
            biezacy = []
            continue
        biezacy.append(l)
    slajdy.append("\n".join(biezacy))
    return "\n".join(naglowek), slajdy


def cofnij(tresc: str) -> str:
    """Zdejmuje znaczniki fragmentów, także zagnieżdżone — powtarza aż do skutku.

    Slajdy oznaczone `RECZNIE` omijamy: ich podział na kroki jest celowy
    i zdjęcie opakowań zniszczyłoby go bezpowrotnie.
    """
    if RECZNIE in tresc:
        naglowek, slajdy = podziel_na_slajdy(tresc)
        # Każdy slajd przycinamy z pustych linii na brzegach, bo złączenie
        # dokłada własne — bez tego plik puchłby o kilka linii na przebieg.
        czyste = [(s if RECZNIE in s else cofnij(s)).strip("\n") for s in slajdy]
        return (naglowek + "\n\n" + "\n\n---\n\n".join(czyste)).lstrip("\n") + "\n"
    wzor = (r"\n*" + re.escape(OTWARCIE) + r"\n+(.*?)\n+"
            + re.escape(ZAMKNIECIE) + r"\n*")
    poprzednie = None
    while poprzednie != tresc:
        poprzednie = tresc
        tresc = re.sub(wzor, r"\n\n\1\n\n", tresc, flags=re.S)
    return re.sub(r"\n{3,}", "\n\n", tresc)


def oznacz(tresc: str) -> str:
    # Najpierw zdejmujemy to, co już jest. Inaczej drugie uruchomienie
    # pakowałoby zawartość istniejącego `div`-a w kolejny `div` — bloki są
    # rozdzielone pustą linią, więc parser widzi znacznik i treść osobno.
    naglowek, slajdy = podziel_na_slajdy(cofnij(tresc))
    sklejone = "\n\n---\n\n".join(oznacz_slajd(s) for s in slajdy)
    return (naglowek + "\n\n" + sklejone).lstrip("\n") + "\n"


def main() -> int:
    argumenty = sys.argv[1:]
    wstecz = "--cofnij" in argumenty
    pliki = [Path(a) for a in argumenty if not a.startswith("--")]
    if not pliki:
        pliki = sorted(Path("slides").glob("*.md"))

    for p in pliki:
        przed = p.read_text(encoding="utf-8")
        po = cofnij(przed) if wstecz else oznacz(przed)
        ile = po.count(OTWARCIE)
        if po != przed:
            p.write_text(po, encoding="utf-8")
        print(f"  {p.name:36s} {ile:3d} fragmentów")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
