# Lab 16 — Cluster Maintenance: upgrade klastra

**12 punktów obowiązkowych + 2 dodatkowe**

## Cel

Podnosisz klaster z laba 02 z **1.36** do **1.37** narzędziem `kubeadm` —
w kolejności, którą wymusza version skew, i z `drain`/`uncordon` tam, gdzie
trzeba. Po tym labie wiesz nie tylko *jakie polecenia*, ale **dlaczego w tej
kolejności** i co się stanie, gdy ją odwrócisz.

## Wymagania wstępne

Klaster z laba 02 musi działać. Na maszynie `cp` (`vagrant ssh cp`):

```bash
kubectl get nodes -o wide
```

Oba node'y powinny raportować `v1.36.x`. Jeśli czegoś brakuje — wróć do
modułu 02.

## Jedna reguła, z której wynika cała kolejność

> **Nic nie może być nowsze od serwera API.**

| Komponent | Dopuszczalny rozjazd względem apiservera |
|---|---|
| kubelet | nigdy nowszy; do **3 minorów** starszy |
| kube-proxy | jak kubelet |
| scheduler, controller-manager | nigdy nowszy; do **1 minora** starszego |
| kubectl | **±1 minor** |

Dlatego: **apiserver → pozostałe komponenty control plane → kubelet**.
Nigdy odwrotnie i nigdy dwa minory na raz.

## Zadania

| # | Co robisz | Pkt |
|---|---|---|
| 1 | repozytorium APT na v1.37, nowy `kubeadm`, `kubeadm upgrade plan` | 3 |
| 2 | `kubeadm upgrade apply` — control plane | 4 |
| 3 | kubelet na `k8s-cp`: `drain` → pakiety → restart → `uncordon` | 3 |
| 4 | worker node: `kubeadm upgrade node` + kubelet | 2 |
| 5 | *(dodatkowe)* wszystkie pakiety z powrotem na `hold` | 2 |

## Na co zwrócić uwagę

- **Repozytorium APT jest przypięte do wersji minor.** Dopóki w
  `/etc/apt/sources.list.d/kubernetes.list` stoi `v1.36`, pakiet 1.37
  **nie istnieje** — `apt-get install` powie „Version not found" i to nie
  jest awaria, tylko brakujący krok.
- **`kubeadm upgrade apply` nie dotyka kubeleta.** Podnosi static Pody
  control plane i etcd; kubelet to osobny pakiet i osobny restart.
  `upgrade plan` mówi o tym wprost — warto przeczytać jego wyjście do końca.
- **`apply` na control plane, `node` na workerze.** `kubeadm upgrade node`
  odświeża tylko lokalną konfigurację kubeleta.
- **Zapomniany `uncordon`** to najczęstszy błąd w tym ćwiczeniu. Sprawdzenie
  zadania 3 i 4 celowo go wyłapuje.
- **Po zadaniu 2 zobaczysz version skew na żywo**: apiserver 1.37, kubelet
  1.36 na obu node'ach, klaster w pełni sprawny. To stan legalny i normalny
  w trakcie każdego upgrade'u.
- **`apt-mark hold`** nie jest ozdobą. Bez niego najbliższy `apt upgrade`
  podniesie kubeleta ponad apiserver i node wypadnie z klastra — awarię
  trudno powiązać z przyczyną, bo nikt niczego świadomie nie aktualizował.

## Czego ten lab nie pokrywa

- **kopii zapasowej i odtwarzania `etcd`** — to rozdział 15 i lab 15.
  Na produkcji migawkę robi się **zawsze** przed `upgrade apply`.
- **klastra HA**, gdzie pozostałe control plane node'y podnosi się przez
  `kubeadm upgrade node`, jeden po drugim.
- **downgrade'u** — nie jest wspierany. Jedyna droga w tył to odtworzenie
  z kopii `etcd`.

## Sprzątanie

Nie ma czego sprzątać — klaster zostaje na nowej wersji. Jeśli chcesz wrócić
do punktu wyjścia:

```bash
cd env/vm/kubeadm
vagrant destroy -f && vagrant up      # maszyny wstaną z powrotem na 1.36
```
