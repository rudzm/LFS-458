#!/usr/bin/env bash
# Przygotowuje maszynę pod `kubeadm init` / `kubeadm join` — ale klastra NIE stawia.
# To jest treść zadań modułu 02 i ma zostać dla kursanta.
#
# Co robi:
#   1. wyłącza swap (kubelet odmawia startu przy włączonym)
#   2. ładuje moduły jądra i ustawia sysctl wymagane przez sieć Podów
#   3. instaluje containerd z cgroupami systemd
#   4. instaluje kubeadm, kubelet, kubectl i crictl z pkgs.k8s.io
#      — celowo w wersji o jeden minor starszej niż klastry kind, żeby lab 16
#        miał co podnosić (`kubeadm upgrade`)
#   5. przypina kubeletowi adres z sieci host-only
#   6. instaluje cilium-cli i pobiera obrazy CNI z wyprzedzeniem
#   7. na `cp` zostawia ~/kubeadm-config.yaml — to samo co flagi `kubeadm init`,
#      zapisane w pliku, do pokazania drugiej drogi instalacji
set -euo pipefail

K8S_MINOR="${K8S_MINOR:-v1.36}"
CILIUM_VER="${CILIUM_VER:-1.20.3}"
CILIUM_CLI_VER="${CILIUM_CLI_VER:-v0.20.1}"
NODE_IP="${NODE_IP:?brak NODE_IP}"

export DEBIAN_FRONTEND=noninteractive

echo "=== [1/8] swap off ==="
swapoff -a
sed -i.bak -E 's@^([^#].*\bswap\b.*)$@# \1@' /etc/fstab
# Ubuntu 24.04 potrafi mieć swap w osobnej jednostce systemd, nie w fstab —
# wyłączamy konkretne jednostki zamiast maskować cały swap.target, bo
# maskowanie targetu potrafi namieszać w zależnościach startu systemd.
for u in $(systemctl list-units --type=swap --no-legend --all 2>/dev/null | awk '{print $1}'); do
  systemctl mask "$u" 2>/dev/null || true
done
swapon --show || echo "    swap wyłączony"

echo "=== [2/8] moduły jądra i sysctl ==="
cat >/etc/modules-load.d/k8s.conf <<'EOM'
overlay
br_netfilter
EOM
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes.conf <<'EOM'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOM
sysctl --system >/dev/null

echo "=== [3/8] /etc/hosts ==="
# Żeby `ping k8s-worker` działał bez DNS-a — przydaje się przy diagnozie.
sed -i '/k8s-cp\|k8s-worker/d' /etc/hosts
cat >>/etc/hosts <<'EOM'
192.168.56.10 k8s-cp
192.168.56.11 k8s-worker
EOM

echo "=== [4/8] containerd ==="
apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gpg containerd

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# Bez SystemdCgroup kubelet i containerd kłócą się o cgroupy i Pody wpadają
# w pętlę restartów — to jedna z klasycznych pułapek ręcznej instalacji.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable  containerd >/dev/null

echo "=== [5/8] kubeadm, kubelet, kubectl, crictl (${K8S_MINOR}) ==="
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl cri-tools
apt-mark hold kubelet kubeadm kubectl >/dev/null

crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock >/dev/null 2>&1 || \
  printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 10\n' >/etc/crictl.yaml

echo "=== [6/8] adres węzła dla kubeleta ==="
# VirtualBox daje każdej maszynie ten sam adres NAT (10.0.2.15) na eth0.
# Bez jawnego --node-ip kubelet zgłosiłby właśnie ten adres jako InternalIP
# węzła — na obu maszynach identyczny — i `kubectl exec`, `logs` oraz sieć
# Podów przestałyby działać w sposób trudny do zdiagnozowania.
printf 'KUBELET_EXTRA_ARGS=--node-ip=%s\n' "$NODE_IP" >/etc/default/kubelet
systemctl daemon-reload
# kubelet bez klastra wpada w pętlę restartów i to jest poprawne — konfigurację
# dostanie dopiero od `kubeadm init` albo `kubeadm join`.
systemctl enable kubelet >/dev/null

echo "=== [7/8] cilium-cli + obrazy CNI ==="
# Kursant instaluje CNI sam (zadanie 2), ale narzędzie i obrazy dajemy
# z wyprzedzeniem: ~500 MiB na maszynę razy osiem stanowisk w jednej sali
# potrafi zająć więcej czasu niż całe zadanie.
CLI_ARCH=amd64
[ "$(uname -m)" = "aarch64" ] && CLI_ARCH=arm64
curl -fsSL --retry 3 \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VER}/cilium-linux-${CLI_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin cilium
chmod +x /usr/local/bin/cilium

for img in "quay.io/cilium/cilium:v${CILIUM_VER}" "quay.io/cilium/operator-generic:v${CILIUM_VER}"; do
  echo "    pobieram $img"
  ctr -n k8s.io images pull "$img" >/dev/null 2>&1 \
    || echo "    (nie udało się — zostanie pobrany w trakcie laba)"
done

echo "=== [8/8] plik konfiguracyjny kubeadm ==="
# Tylko na control plane: `kubeadm init --config` robi to samo, co flagi
# z zadania 1. Wersję bierzemy z zainstalowanego pakietu, żeby plik pasował
# do maszyny także po zmianie K8S_MINOR.
if [ "$(hostname)" = "k8s-cp" ]; then
  WERSJA=$(kubeadm version -o short)
  # Heredoc w cudzysłowach: komentarze w pliku zawierają polecenia
  # w backtickach, a bez cudzysłowów powłoka by je wykonała.
  cat >/home/vagrant/kubeadm-config.yaml <<'EOM'
# To samo, co flagi `kubeadm init` z zadania 1 — tylko zapisane w pliku:
#
#   sudo kubeadm init --config ~/kubeadm-config.yaml
#
# Plik da się trzymać w repozytorium, przejrzeć w code review i użyć
# ponownie. Wszystkie pola z wartościami domyślnymi wypisze:
#
#   kubeadm config print init-defaults
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.56.10     # = --apiserver-advertise-address
  bindPort: 6443
nodeRegistration:
  name: k8s-cp                        # nazwa node'a w klastrze
  criSocket: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
# wersja pakietów zainstalowanych na tej maszynie
kubernetesVersion: WERSJA_PAKIETOW
networking:
  podSubnet: 10.244.0.0/16            # = --pod-network-cidr
  serviceSubnet: 10.96.0.0/12
---
# Tego we flagach `kubeadm init` nie ustawisz — tylko w pliku.
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd                 # zgodnie z SystemdCgroup w containerd
EOM
  sed -i "s/WERSJA_PAKIETOW/${WERSJA}/" /home/vagrant/kubeadm-config.yaml
  chown vagrant:vagrant /home/vagrant/kubeadm-config.yaml
  if kubeadm config validate --config /home/vagrant/kubeadm-config.yaml >/dev/null 2>&1; then
    echo "    ~/kubeadm-config.yaml gotowy (${WERSJA})"
  else
    echo "    UWAGA: kubeadm odrzuca ~/kubeadm-config.yaml — sprawdź: kubeadm config validate --config ~/kubeadm-config.yaml"
  fi
else
  echo "    pomijam — plik jest tylko na cp"
fi

echo
echo "=== maszyna gotowa — klastra nie ma i o to chodzi ==="

printf 'kubeadm: %s\n' "$(kubeadm version -o short 2>/dev/null || kubeadm version)"
printf 'swap:    %s\n' "$(swapon --show | wc -l) wpisów"
printf 'moduły:  %s\n' "$(lsmod | grep -c br_netfilter) × br_netfilter"
printf 'node-ip: %s\n' "$NODE_IP"
CILIUM_WER=$(cilium version --client 2>/dev/null | sed -n '1p'); printf 'cilium:  %s\n' "${CILIUM_WER:-niedostępny}"
