#!/usr/bin/env bash
# Odczytuje jedną odpowiedź z arkusza modułu.
#
#   scripts/odpowiedz.sh 01 liczba-wezlow
#
# Arkusz to zwykły plik `~/odpowiedzi/lab-NN.txt` w formacie `klucz=wartość`,
# po jednej parze na linię. Puste linie i komentarze (`#`) są pomijane.
#
# Katalog domowy, a nie repozytorium: ścieżka jest wtedy ta sama niezależnie
# od tego, skąd uruchomiono `labctl` — binarka bywa podlinkowana z
# /usr/local/bin. Plik, a nie ConfigMapa, bo kursant zapisuje odpowiedzi już
# w pierwszym module, a ConfigMapy omawiamy dopiero w ósmym.
set -euo pipefail

MODUL="${1:?podaj numer modułu, np. 01}"
KLUCZ="${2:?podaj nazwę klucza}"
PLIK="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-${MODUL}.txt"

[[ -f "$PLIK" ]] || exit 0        # brak arkusza = brak odpowiedzi, nie błąd

sed -e 's/[[:space:]]*#.*$//' "$PLIK" \
  | grep -E "^[[:space:]]*${KLUCZ}[[:space:]]*=" \
  | head -1 \
  | cut -d= -f2- \
  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
