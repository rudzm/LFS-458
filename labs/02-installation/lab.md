# Lab 02 — klaster od zera

**15 punktów obowiązkowych**

## Cel

Zbudujesz klaster `kubeadm`-em na dwóch maszynach i zobaczysz, co dokładnie
zostaje na dysku po instalacji. To jedyny moduł, w którym control plane jest
naprawdę Twój — reszta szkolenia korzysta z gotowego klastra Kind.

## Przygotowanie

Środowisko `vagrant-kubeadm` musi być postawione: `labctl env up vagrant-kubeadm`
(albo `labctl lab 02`, które zrobi to samo). Pierwsze uruchomienie pobiera obraz systemu i prowizjonuje
dwie maszyny — trwa kilkanaście minut, więc warto puścić je przed przerwą.

```bash
cd env/vm/kubeadm
vagrant status
vagrant ssh cp        # k8s-cp,     192.168.56.10
vagrant ssh worker    # k8s-worker, 192.168.56.11
```

Na maszynach jest już wszystko oprócz klastra: containerd, `kubeadm`,
`kubelet`, `kubectl`, wyłączony swap, moduły jądra i sysctl.

> Swap sam w sobie jest obsługiwany — wyłączamy go, bo kubelet startuje
> z `failSwapOn: true` i dopóki tego nie zmienisz, odmówi uruchomienia.
> Tego samego pilnuje preflight check `kubeadm init`.
Sprawdź to przed startem — będzie wiadomo, czego *nie* trzeba robić:

```bash
vagrant ssh cp -c "swapon --show; lsmod | grep br_netfilter; kubeadm version -o short"
```

## Ważne: gdzie pracujesz i skąd weryfikator bierze klaster

Cały moduł robisz **na maszynach**, przez `vagrant ssh cp` i `vagrant ssh worker`.
`kubectl` konfigurujesz na `cp` i tam zostaje — kubeconfig nie trafia na host,
więc klaster z tego modułu nie miesza się z `kind-lfs458`.

Weryfikator sam łączy się z maszyną `cp`. Dopóki nie ma na niej klastra,
każdy check jest czerwony i `labctl` mówi o braku połączenia z klastrem
na maszynie `cp`. To poprawny komunikat, nie awaria weryfikatora.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| postawić control plane | `sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.56.10` |
| zobaczyć, co zrobi init | `sudo kubeadm init --dry-run` |
| polecenie dołączenia | `kubeadm token create --print-join-command` |
| listę tokenów | `kubeadm token list` |
| ważność certyfikatów | `sudo kubeadm certs check-expiration` |
| konfigurację klastra | `kubectl -n kube-system get cm kubeadm-config -o yaml` |
| static Pody na dysku | `sudo ls -l /etc/kubernetes/manifests` |
| konfigurację kubeleta | `sudo cat /var/lib/kubelet/config.yaml` |
| zacząć od nowa | `sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d ~/.kube` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | `kubeadm init` + `kubectl` skonfigurowany na `cp` | 4 |
| 2 | Sieć Podów — node przechodzi w `Ready` | 3 |
| 3 | `kubeadm join` worker node'a | 4 |
| 4 | **Pytania ABCD** o to, co zostawił kubeadm: pula Podów, endpoint, katalog static Podów, ważność CA | 4 |

## Na co zwrócić uwagę

- **Zadanie 1** — `kubeadm init` wypisuje na końcu trzy polecenia do
  skonfigurowania `kubectl` oraz gotowe `kubeadm join`. **Skopiuj cały ten
  blok do pliku**, zanim wyczyścisz terminal.
- **Zadanie 1, wersja z pliku** — `~/kubeadm-config.yaml` na `cp` opisuje
  tę samą instalację: `InitConfiguration` (adres, nazwa node'a),
  `ClusterConfiguration` (wersja, pule adresów) i `KubeletConfiguration`
  (cgroup driver — tego flagami `kubeadm init` nie ustawisz). Na produkcji
  wybiera się zwykle plik: da się go wersjonować i przejrzeć przed instalacją.
- **Zadanie 2** — zanim zainstalujesz sieć, zajrzyj do
  `kubectl describe node k8s-cp`. Sekcja `Conditions` mówi wprost:
  `container runtime network not ready: NetworkReady=false … cni plugin not initialized`.
  To najbardziej pouczający komunikat w całym module.
- **Zadanie 3** — jeśli `kubeadm join` zawiesza się na
  `[preflight] Running pre-flight checks`, sprawdź, czy maszyny widzą się po
  sieci: `vagrant ssh worker -c "ping -c2 192.168.56.10"`.
- Po nieudanej próbie **zawsze** `sudo kubeadm reset -f` przed kolejnym
  podejściem. `reset` nie czyści `/etc/cni/net.d` — usuń ten katalog ręcznie.

## Wariant bez maszyn wirtualnych

Jeśli stanowisko nie udźwignie VirtualBoksa, zadań 1–3 nie zrobisz — ale
**artefakty z zadania 4 obejrzysz w klastrze Kind**, bo Kind też stawia klaster
`kubeadm`-em. Wejdź do node'a jak do zwykłego kontenera:

```bash
docker exec -it lfs458-control-plane bash      # albo: nerdctl exec -it …

ls -l /etc/kubernetes/manifests
ls -l /etc/kubernetes/pki
cat /var/lib/kubelet/config.yaml
kubeadm certs check-expiration
crictl ps                                       # kontenery widziane przez CRI
```

To ten sam układ katalogów, te same static Pody i ta sama ConfigMapa
`kubeadm-config`. Czego nie zobaczysz: `kubeadm init` w akcji, dołączania node'a
i preflight checks — czyli dokładnie tego, po co jest to środowisko.

## Sprzątanie

`labctl cleanup 02` usuwa tylko namespace `lfs458-m02`. **Klaster na maszynach
zostaje**, żeby można było do niego wrócić w przerwie — żaden późniejszy moduł
go już jednak nie potrzebuje (High Availability z modułu 15 pracuje na osobnym
klastrze Kind).

Gdy skończysz z nim na dobre:

```bash
labctl env down vagrant-kubeadm     # albo: cd env/vm/kubeadm && vagrant destroy -f
```
