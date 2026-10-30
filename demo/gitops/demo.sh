#!/usr/bin/env bash
# Pokaz GitOps z dodatku „GitOps” — Argo CD i serwer git w klastrze kind-basic.
#
#   demo/gitops/demo.sh postaw      Argo CD + serwer git + kopia robocza w ~/gitops-demo
#   demo/gitops/demo.sh wypchnij    git push z ~/gitops-demo i natychmiastowe odświeżenie
#   demo/gitops/demo.sh ui          hasło admina i UI na https://localhost:9443
#   demo/gitops/demo.sh usun        sprząta wszystko, łącznie z ~/gitops-demo
#
# Commity robi się ręcznie w ~/gitops-demo, na oczach grupy: o to w pokazie
# chodzi. `wypchnij` tylko je wysyła i każe Argo CD od razu sprawdzić repo.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
TU="$(cd "$(dirname "$0")" && pwd)"
ARGOCD_WERSJA=v3.5.5
KOPIA="$HOME/gitops-demo"
REPO=git://localhost:9418/aplikacja.git
k() { kubectl --context "$CTX" "$@"; }

# Serwer git jest w klastrze, więc z laptopa sięgamy do niego tunelem.
# Tunel startuje w tle i zostaje — kolejne `wypchnij` z niego korzystają.
tunel() {
  git ls-remote "$REPO" >/dev/null 2>&1 && return 0
  nohup kubectl --context "$CTX" -n gitops-git port-forward svc/git 9418:9418 \
    >/dev/null 2>&1 &
  echo $! > "$TU/.tunel.pid"
  for _ in $(seq 20); do
    git ls-remote "$REPO" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "tunel do serwera git nie wstał — sprawdź: k -n gitops-git get pods" >&2
  return 1
}

# Argo CD pyta repo co ~3 minuty, a repo-server pamięta rewizje równie długo.
# Na produkcji skraca to webhook z GitHuba/GitLaba; tu — hard refresh.
odswiez() {
  k -n argocd annotate application witryna argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

postaw() {
  echo "→ Argo CD $ARGOCD_WERSJA"
  k create namespace argocd --dry-run=client -o yaml | k apply -f - >/dev/null
  # --server-side: CRD ApplicationSet jest za duży na adnotację last-applied.
  k apply -n argocd --server-side --force-conflicts \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_WERSJA/manifests/install.yaml" >/dev/null

  echo "→ serwer git"
  k apply -f "$TU/serwer-git.yaml" >/dev/null
  k -n gitops-git rollout status deploy/git --timeout=180s >/dev/null
  k -n argocd rollout status deploy/argocd-repo-server --timeout=300s >/dev/null
  k -n argocd rollout status sts/argocd-application-controller --timeout=300s >/dev/null

  echo "→ repozytorium aplikacji w $KOPIA"
  tunel
  if [ ! -d "$KOPIA/.git" ]; then
    mkdir -p "$KOPIA"
    cp "$TU"/aplikacja/*.yaml "$KOPIA/"
    git -C "$KOPIA" init --quiet -b main
    git -C "$KOPIA" add .
    git -C "$KOPIA" -c user.name=Trener -c user.email=trener@lfs458.local \
      commit --quiet -m "Pierwsza wersja witryny"
    git -C "$KOPIA" remote add origin "$REPO"
    # `git wypchnij` w kopii roboczej = push + hard refresh, bez wracania do repo szkolenia.
    git -C "$KOPIA" config alias.wypchnij "!$TU/demo.sh wypchnij"
  fi
  # Po restarcie Poda serwera repo jest puste — wypychamy, co mamy lokalnie.
  git -C "$KOPIA" push --quiet origin main

  echo "→ Application witryna"
  k apply -f "$TU/application.yaml" >/dev/null
  for _ in $(seq 60); do
    [ "$(k -n argocd get application witryna -o jsonpath='{.status.health.status}' 2>/dev/null)" = Healthy ] && break
    sleep 2
  done
  echo
  k -n argocd get application witryna
  echo
  echo "gotowe. Dalej: cd $KOPIA, zmień coś, git commit -am '…' && git wypchnij"
}

wypchnij() {
  tunel
  git -C "$KOPIA" push origin main
  odswiez
  echo "wysłane — Argo CD wdroży zmianę w ciągu ~30 s:"
  echo "  kubectl -n argocd get application witryna -w"
}

ui() {
  echo "użytkownik: admin"
  echo "hasło:      $(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  echo "adres:      https://localhost:9443   (certyfikat samopodpisany — zaakceptuj)"
  echo
  # 8443 zajmuje Ingress klastra kind-basic, stąd 9443.
  k -n argocd port-forward svc/argocd-server 9443:443
}

usun() {
  # Najpierw Application: jej finalizer usuwa wdrożone obiekty, ale potrzebuje
  # do tego działającego kontrolera, więc namespace argocd musi jeszcze żyć.
  k -n argocd delete application witryna --ignore-not-found --wait=true --timeout=120s || true
  k delete namespace witryna gitops-git argocd --ignore-not-found --wait=true
  # Klastrowe resztki instalacji: CRD i role nie mieszkają w namespace argocd.
  k delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found
  k get clusterrole,clusterrolebinding -o name | grep -E '/argocd-' | xargs -r kubectl --context "$CTX" delete >/dev/null
  if [ -f "$TU/.tunel.pid" ]; then
    kill "$(cat "$TU/.tunel.pid")" 2>/dev/null || true
    rm -f "$TU/.tunel.pid"
  fi
  rm -rf "$KOPIA"
  echo "posprzątane"
}

case "${1:-}" in
  postaw|wypchnij|ui|usun) "$1" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
