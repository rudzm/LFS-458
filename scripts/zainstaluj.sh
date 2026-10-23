#!/usr/bin/env bash
# Przygotowuje stanowisko do szkolenia LFS458.
#
# Najpierw sprawdza, czego brakuje, i pokazuje listę. Potem pyta, czy ma to
# zainstalować. Nic nie robi bez zgody i nie zostawia użytkownika z listą
# poleceń do ręcznego przepisania.
#
#   ./scripts/zainstaluj.sh              sprawdź i zaproponuj instalację
#   ./scripts/zainstaluj.sh --sprawdz    tylko sprawdź, niczego nie instaluj
#   ./scripts/zainstaluj.sh --tak        instaluj bez pytania (CI, automatyzacja)
#   ./scripts/zainstaluj.sh --bez-slajdow  pomiń marp (potrzebny tylko do prezentacji)
set -euo pipefail

# ——— wersje w jednym miejscu ————————————————————————————————————————
KUBECTL_VER="${KUBECTL_VER:-v1.37.1}"     # ta sama linia co klaster szkoleniowy
KIND_VER="${KIND_VER:-v0.33.0}"           # min. 0.26 — niżej kindnet nie wymusza NetworkPolicy
HELM_VER="${HELM_VER:-v4.3.1}"
VAGRANT_VER="${VAGRANT_VER:-2.4.9}"
MARP_VER="${MARP_VER:-v4.5.1}"

CEL="${CEL:-$HOME/.local/bin}"
TRYB=pytaj          # pytaj | sprawdz | tak
ZE_SLAJDAMI=1

for arg in "$@"; do
  case "$arg" in
    --sprawdz|--check)        TRYB=sprawdz ;;
    --tak|--yes|-y)           TRYB=tak ;;
    --bez-slajdow|--no-marp)  ZE_SLAJDAMI=0 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "nieznany argument: $arg" >&2; exit 2 ;;
  esac
done

zielony() { printf '\033[32m%s\033[0m\n' "$1"; }
zolty()   { printf '\033[33m%s\033[0m\n' "$1"; }
czerw()   { printf '\033[31m%s\033[0m\n' "$1"; }
szary()   { printf '\033[2m%s\033[0m\n' "$1"; }
grubo()   { printf '\033[1m%s\033[0m\n' "$1"; }

case "$(uname -m)" in
  x86_64)  ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) czerw "nieobsługiwana architektura: $(uname -m)"; exit 1 ;;
esac

TYMCZASOWY="$(mktemp -d)"
trap 'rm -rf "$TYMCZASOWY"' EXIT

# ——— rozpoznanie ———————————————————————————————————————————————————
# Trzy listy, bo każda wymaga czego innego: binarki idą do katalogu
# użytkownika, pakiety wymagają roota, a grupy — przelogowania.

BINARKI=()      # kubectl kind helm vagrant marp
PAKIETY=()      # docker.io virtualbox jq openssl python3-yaml
GRUPY=()        # docker vboxusers

ma_wersje() {   # narzędzie, oczekiwana wersja
  command -v "$1" >/dev/null 2>&1 || return 1
  local obecna
  # Każde narzędzie pytamy o wersję tak, żeby odpowiedziało LOKALNIE.
  # `kubectl version` bez --client łączy się z klastrem i przy nieosiągalnym
  # kontekście wisi aż do timeoutu.
  case "$1" in
    kubectl) obecna="$(timeout 10 "$1" version --client -o yaml 2>/dev/null || true)" ;;
    helm)    obecna="$(timeout 10 "$1" version --short 2>/dev/null || true)" ;;
    *)       obecna="$(timeout 10 "$1" --version 2>/dev/null || true)" ;;
  esac
  [[ "$obecna" == *"${2#v}"* ]]
}

status_binarki() {   # narzędzie, wersja, opis
  if ma_wersje "$1" "$2"; then
    zielony "  ✓ $1 $2"
  elif command -v "$1" >/dev/null 2>&1; then
    zolty "  ~ $1 — inna wersja niż $2  ($3)"; BINARKI+=("$1")
  else
    czerw "  ✗ $1  ($3)"; BINARKI+=("$1")
  fi
}

status_pakietu() {   # polecenie, pakiet apt, opis
  if command -v "$1" >/dev/null 2>&1; then
    zielony "  ✓ $1"
  else
    czerw "  ✗ $1  ($3)"; PAKIETY+=("$2")
  fi
}

echo
grubo "Sprawdzam stanowisko"
echo
szary "Narzędzia użytkownika (→ $CEL)"
status_binarki kubectl "$KUBECTL_VER" "rozmowa z API klastra"
status_binarki kind    "$KIND_VER"    "klaster szkoleniowy"
status_binarki helm    "$HELM_VER"    "moduł 13"
status_binarki vagrant "$VAGRANT_VER" "moduł 02 — maszyny wirtualne"
[ "$ZE_SLAJDAMI" = 1 ] && status_binarki marp "$MARP_VER" "renderowanie prezentacji"

echo
szary "Pakiety systemowe (instalacja wymaga hasła)"
status_pakietu jq      jq      "czytanie JSON-a w kilku labach"
status_pakietu openssl openssl "certyfikat w module 09"
status_pakietu VBoxManage virtualbox "moduł 02 — hipernadzorca"

if docker info >/dev/null 2>&1; then
  zielony "  ✓ silnik kontenerów — działa"
elif command -v docker >/dev/null 2>&1; then
  zolty "  ~ docker zainstalowany, ale demon nie odpowiada z tego konta"
  id -nG | tr ' ' '\n' | grep -qx docker || GRUPY+=(docker)
else
  czerw "  ✗ docker  (klaster szkoleniowy działa w kontenerach)"
  PAKIETY+=(docker.io)
  GRUPY+=(docker)
fi

if python3 -c 'import yaml' 2>/dev/null; then
  zielony "  ✓ python3 + PyYAML"
else
  czerw "  ✗ PyYAML  (labctl bez niego nie wystartuje)"
  PAKIETY+=(python3-yaml)
fi

# Dostęp do sterownika VirtualBoksa — bez niego maszyny się nie uruchomią.
if command -v VBoxManage >/dev/null 2>&1 && ! [ -r /dev/vboxdrv ]; then
  id -nG | tr ' ' '\n' | grep -qx vboxusers || GRUPY+=(vboxusers)
fi

DO_ZROBIENIA=$(( ${#BINARKI[@]} + ${#PAKIETY[@]} + ${#GRUPY[@]} ))

echo
if [ "$DO_ZROBIENIA" -eq 0 ]; then
  zielony "Stanowisko jest gotowe — nie brakuje niczego."
  echo
  exit 0
fi

grubo "Do uzupełnienia"
[ ${#BINARKI[@]} -gt 0 ] && echo "  · binarki:  ${BINARKI[*]}"
[ ${#PAKIETY[@]} -gt 0 ] && echo "  · pakiety:  ${PAKIETY[*]}  (wymaga hasła administratora)"
[ ${#GRUPY[@]}   -gt 0 ] && echo "  · grupy:    ${GRUPY[*]}  (wymaga przelogowania)"
echo

[ "$TRYB" = sprawdz ] && exit 0

if [ "$TRYB" = pytaj ]; then
  if [ ! -t 0 ]; then
    zolty "Sesja nie jest interaktywna — nie mogę zapytać o zgodę."
    szary "Uruchom skrypt w terminalu albo dodaj --tak."
    exit 1
  fi
  read -r -p "  Zainstalować to teraz? [T/n] " odp
  case "${odp,,}" in
    ""|t|tak|y|yes) ;;
    *) echo; szary "Nic nie zmieniam — zrób to po swojemu i uruchom skrypt ponownie."; echo; exit 0 ;;
  esac
  echo
fi

# ——— instalacja ————————————————————————————————————————————————————

pobierz() { curl -fsSL --retry 3 --connect-timeout 20 -o "$2" "$1"; }
wstaw()   { mkdir -p "$CEL"; install -m 0755 "$1" "$CEL/$2"; zielony "   → $CEL/$2"; }

instaluj_kubectl() {
  local baza="https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/${ARCH}"
  pobierz "$baza/kubectl" "$TYMCZASOWY/kubectl"
  pobierz "$baza/kubectl.sha256" "$TYMCZASOWY/kubectl.sha256"
  (cd "$TYMCZASOWY" && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --quiet)
  wstaw "$TYMCZASOWY/kubectl" kubectl
}

instaluj_kind() {
  pobierz "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-${ARCH}" "$TYMCZASOWY/kind"
  wstaw "$TYMCZASOWY/kind" kind
}

instaluj_helm() {
  local plik="helm-${HELM_VER}-linux-${ARCH}.tar.gz"
  pobierz "https://get.helm.sh/${plik}" "$TYMCZASOWY/$plik"
  pobierz "https://get.helm.sh/${plik}.sha256sum" "$TYMCZASOWY/${plik}.sha256sum"
  (cd "$TYMCZASOWY" && sha256sum --check --quiet "${plik}.sha256sum")
  tar -xzf "$TYMCZASOWY/$plik" -C "$TYMCZASOWY" --strip-components=1 "linux-${ARCH}/helm"
  wstaw "$TYMCZASOWY/helm" helm
}

instaluj_vagrant() {
  # HashiCorp wydaje Vagranta jako zwykłą binarkę — nie trzeba do tego roota
  # ani repozytorium apt.
  pobierz "https://releases.hashicorp.com/vagrant/${VAGRANT_VER}/vagrant_${VAGRANT_VER}_linux_${ARCH}.zip" \
          "$TYMCZASOWY/vagrant.zip"
  unzip -oq "$TYMCZASOWY/vagrant.zip" vagrant -d "$TYMCZASOWY"
  wstaw "$TYMCZASOWY/vagrant" vagrant
}

instaluj_marp() {
  local plik="marp-cli-${MARP_VER}-linux.tar.gz"
  [ "$ARCH" = arm64 ] && plik="marp-cli-${MARP_VER}-linux-arm64.tar.gz"
  pobierz "https://github.com/marp-team/marp-cli/releases/download/${MARP_VER}/${plik}" \
          "$TYMCZASOWY/marp.tgz"
  tar -xzf "$TYMCZASOWY/marp.tgz" -C "$TYMCZASOWY" marp
  wstaw "$TYMCZASOWY/marp" marp
}

if [ ${#PAKIETY[@]} -gt 0 ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    czerw "Ten skrypt instaluje pakiety tylko przez apt-get, a go tu nie ma."
    szary "Pakiety do uzupełnienia: ${PAKIETY[*]}"
    exit 1
  fi
  grubo "Pakiety systemowe"
  szary "  sudo poprosi o hasło"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PAKIETY[@]}"
  zielony "  zainstalowane: ${PAKIETY[*]}"
  echo
fi

if [ ${#BINARKI[@]} -gt 0 ]; then
  grubo "Binarki"
  for narzedzie in "${BINARKI[@]}"; do
    echo "  $narzedzie"
    "instaluj_$narzedzie"
  done
  echo
fi

if [ ${#GRUPY[@]} -gt 0 ]; then
  grubo "Grupy"
  for grupa in "${GRUPY[@]}"; do
    if getent group "$grupa" >/dev/null 2>&1; then
      sudo usermod -aG "$grupa" "$USER"
      zielony "  dodano $USER do grupy $grupa"
    fi
  done
  echo
  zolty "  Grupy zaczną działać po przelogowaniu — wyloguj się i zaloguj ponownie."
  echo
fi

case ":$PATH:" in
  *":$CEL:"*) ;;
  *) zolty "Uwaga: $CEL nie jest w PATH — binarki nie będą widoczne."
     if [ -w "$HOME/.bashrc" ] && ! grep -q 'HOME/.local/bin' "$HOME/.bashrc"; then
       echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
       zielony "  dopisałem to do ~/.bashrc — zadziała w nowej powłoce"
     fi ;;
esac

zielony "Gotowe."
szary "Stan stanowiska w każdej chwili:  make doctor"
echo
