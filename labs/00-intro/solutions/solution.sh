#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 00 — dla trenera.
# Zadania 2 i 5 to pytania ABCD, odpowiada się na nie w `labctl lab 00`;
# skrypt wypisuje tylko poprawne odpowiedzi do porównania.
#   ./labs/00-intro/solutions/solution.sh && labctl check 00
set -euo pipefail

D="${CONTAINER_CLI:-docker}"
CTX="${KUBECONTEXT:-kind-lfs458}"

echo "→ zadanie 1: pierwszy kontener"
$D inspect lfs458-demo >/dev/null 2>&1 || $D run -d --name lfs458-demo nginx:1.27-alpine
sleep 2

echo "→ zadanie 2: dwa widoki tego samego procesu"
echo "   PID w środku:  $($D exec lfs458-demo ps -o pid,args | awk '/nginx: master/ {print $1; exit}')"
echo "   PID na hoście: $($D inspect -f '{{.State.Pid}}' lfs458-demo)"
echo "   hostname:      $($D exec lfs458-demo hostname)"
echo "   system:        $($D exec lfs458-demo sh -c '. /etc/os-release; echo "$ID"')"
echo "   jądro:         $($D exec lfs458-demo uname -r)   (host: $(uname -r))"

echo "→ zadanie 3: limit pamięci"
$D inspect lfs458-limit >/dev/null 2>&1 || $D run -d --name lfs458-limit --memory 64m nginx:1.27-alpine
sleep 1
echo "   memory.max:    $($D exec lfs458-limit cat /sys/fs/cgroup/memory.max)"

echo "→ zadanie 4: warstwa zapisu"
$D exec lfs458-demo touch /tmp/slad.txt
$D diff lfs458-demo | grep slad
$D inspect lfs458-drugi >/dev/null 2>&1 || $D run -d --name lfs458-drugi nginx:1.27-alpine
sleep 1
$D exec lfs458-drugi test -e /tmp/slad.txt && echo "   BŁĄD: plik jest" || echo "   w lfs458-drugi pliku nie ma"

echo "→ zadanie 5: obraz i runtime"
echo "   warstw:        $($D image inspect -f '{{len .RootFS.Layers}}' nginx:1.27-alpine)"
echo "   runtime:       $(kubectl --context "$CTX" get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')"
echo "   obraz node'a:  $($D inspect -f '{{.Config.Image}}' lfs458-worker | cut -d@ -f1)"
echo "   kontenerów:    $($D exec lfs458-control-plane crictl ps -q | wc -l | tr -d ' ')"

echo
echo "Gotowe. Weryfikacja: labctl check 00"
