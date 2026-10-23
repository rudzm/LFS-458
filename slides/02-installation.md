---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 2 · Installation and Configuration'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Installation and Configuration

## Rozdział 2 · lab `02`

Od pustych maszyn do działającego klastra —
i co dokładnie zostaje po instalacji na dysku

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Getting started** — co trzeba przygotować przed instalacją
2. **Minikube** — klaster na jedno kliknięcie i jego granice
3. **kubeadm** — narzędzie referencyjne projektu
4. **Pozostałe narzędzia** — kind, k3s, kops, dostawcy zarządzani
5. **Lab 02** — stawiasz klaster własnymi rękami

</div>

---

<!-- _class: sekcja -->

# 1. Zanim zainstalujesz

---

# Wymagania, które blokują instalację

<div data-marpit-fragment>

| Wymaganie | Dlaczego | Jak sprawdzić |
|---|---|---|
| **swap wyłączony** — albo jawne `failSwapOn: false` | blokadą nie jest sam swap, tylko domyślne `failSwapOn: true` | `swapon --show` |
| moduły `br_netfilter`, `overlay` | ruch mostkowany musi widzieć iptables | `lsmod \| grep br_netfilter` |
| `net.ipv4.ip_forward=1` | routing między Podami | `sysctl net.ipv4.ip_forward` |
| **unikalne** hostname, MAC, `product_uuid` | klonowane VM-ki zderzają się w klastrze | `sudo cat /sys/class/dmi/id/product_uuid` |
| container runtime z **CRI** | kubelet nie mówi inaczej | `crictl version` |
| 2 CPU na control plane | twardy preflight check | `nproc` |

</div>

<div data-marpit-fragment>

> `kubeadm init` sam sprawdza te warunki i **zatrzymuje się**, zanim cokolwiek
> popsuje. Komunikaty preflight są konkretne — warto je przeczytać, a nie omijać
> flagą `--ignore-preflight-errors`.

</div>

---

# cgroup driver — klasyczna pułapka

<div data-marpit-fragment>

Kubelet i container runtime muszą używać **tego samego** sterownika cgroups.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Jak ma być

</div>

* systemd zarządza cgroupami
* containerd: `SystemdCgroup = true`
* kubelet: `cgroupDriver: systemd`

</div>
<div>

<div data-marpit-fragment>

### Gdy się rozjedzie

</div>

* Pody w pętli restartów
* limity pamięci nie działają
* komunikaty mylą, bo nic nie mówi
  wprost o cgroupach

</div>
</div>

<div data-marpit-fragment>

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml
sudo systemctl restart containerd
```

</div>

<div data-marpit-fragment>

*W labie masz to już ustawione — ale to pierwsza rzecz do sprawdzenia,
gdy stawiasz klaster od zera na swoim sprzęcie.*

</div>

---

<!-- _class: sekcja -->

# 2. Minikube

---

# Minikube — do nauki i do laptopa

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Co daje

</div>

* jedno polecenie: `minikube start`
* dodatki: `addons enable ingress`
* wiele sterowników: docker, KVM,
  VirtualBox
* `minikube dashboard`

</div>
<div>

<div data-marpit-fragment>

### Czego nie daje

</div>

* **jeden node** w typowym użyciu
* nie zobaczysz rozmieszczania Podów
  po node'ach
* nie zobaczysz HA ani `drain`
* inne zachowanie sieci niż produkcja

</div>
</div>

<div data-marpit-fragment>

> Dlatego my używamy **Kind** — trzy node'y w kontenerach, bliżej prawdy
> o rozmieszczaniu i sieci, a stawia się równie szybko.

</div>

<div data-marpit-fragment>

```bash
minikube start --nodes 3 --driver docker   # da się, ale rzadko tak się robi
```

</div>

---

<!-- _class: sekcja -->

# 3. kubeadm

---

# kubeadm robi dokładnie trzy rzeczy

<div data-marpit-fragment>

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.56.10
```

</div>

<div data-marpit-fragment>

1. **Generuje PKI** — CA klastra i certyfikaty komponentów w `/etc/kubernetes/pki`
2. **Zapisuje static Pody** do `/etc/kubernetes/manifests` — `kube-apiserver`,
   `etcd`, `kube-scheduler`, `kube-controller-manager`
3. **Bootstrapuje kubelet** i zapisuje konfigurację klastra w ConfigMapie
   `kubeadm-config`

</div>

<div data-marpit-fragment>

Czego **nie** robi: nie instaluje CNI plugina. Dlatego zaraz po `init`
node jest `NotReady` — i to jest poprawne.

</div>

---

# Co zostaje na dysku

<div data-marpit-fragment>

```bash
/etc/kubernetes/
├── admin.conf       # kubeconfig administratora
├── manifests/       # static Pody: etcd, apiserver, scheduler, controller-manager
└── pki/             # CA i certyfikaty — ważne 1 rok!
```

</div>

<div data-marpit-fragment>

| Chcę zobaczyć | Polecenie |
|---|---|
| ważność certyfikatów | `sudo kubeadm certs check-expiration` |
| konfigurację klastra | `kubectl -n kube-system get cm kubeadm-config -o yaml` |
| ustawienia kubeleta | `sudo cat /var/lib/kubelet/config.yaml` |

</div>

<div data-marpit-fragment>

> **Certyfikaty wygasają po roku.** Klaster nietknięty 13 miesięcy przestaje
> działać; `kubeadm certs renew all` je odnawia.

</div>

---

# Dołączanie node'a

<div data-marpit-fragment>

```bash
# na control plane
kubeadm token create --print-join-command

# na node'ie roboczym
sudo kubeadm join 192.168.56.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:1234…
```

</div>

<div data-marpit-fragment>

Co się dzieje przy `join`:

</div>

<div data-marpit-fragment>

1. node pobiera CA klastra i **weryfikuje je** odciskiem z `--discovery-token-ca-cert-hash`
2. tokenem uwierzytelnia się do API i prosi o certyfikat dla kubeleta
3. apiserver podpisuje CSR, kubelet startuje i rejestruje obiekt `Node`

</div>

<div data-marpit-fragment>

> Token żyje **24 godziny**. To nie awaria, gdy po dniu `join` przestaje
> działać — wygeneruj nowy.

</div>

---

<!-- _class: sekcja -->

# 4. Pozostałe narzędzia

---

# Czym jeszcze stawia się klastry

<div data-marpit-fragment>

| Narzędzie | Nisza | Uwaga |
|---|---|---|
| **kind** | CI i nauka | node'y jako kontenery, *tego używamy* |
| **k3s** | brzeg sieci, IoT, małe wdrożenia | jedna binarka, domyślnie SQLite zamiast etcd |
| **kops** | AWS | zarządza też infrastrukturą |
| **kubespray** | on-premises | Ansible na wierzchu kubeadm |
| **EKS / AKS / GKE** | chmura | control plane jako usługa dostawcy |

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Co zyskujesz u dostawcy**

</div>

* control plane utrzymuje ktoś inny
* aktualizacje jednym kliknięciem
* integracja z LB i dyskami chmury

</div>
<div>

<div data-marpit-fragment>

**Co tracisz**

</div>

* dostęp do `etcd` i flag apiservera
* część zadań z tego szkolenia
  jest tam **niewykonalna**

</div>
</div>

---

<!-- _class: lab -->

# Lab 02

<div data-marpit-fragment>

**15 punktów + 3 dodatkowe · dwie maszyny wirtualne**

</div>

<div data-marpit-fragment>

```bash
labctl lab 02
```

</div>

<div data-marpit-fragment>

Postawisz control plane `kubeadm init`-em, dołożysz CNI plugin, dołączysz
worker node i **przeczytasz, co kubeadm zostawił na dysku**: pulę adresów
Podów, endpoint apiservera, katalog static Podów i datę wygaśnięcia CA.

</div>

<div data-marpit-fragment>

> Checki tego modułu lecą na kontekst `kubeadm-lfs458`, który powstaje dopiero
> w zadaniu 1. Dopóki go nie ma, wszystko jest czerwone — **i tak ma być**.

</div>

---

# Co warto zapamiętać

* preflight checks `kubeadm init` są Twoim przyjacielem — czytaj je
* **swap wyłączony** i **zgodny cgroup driver** to dwa najczęstsze blokery
* `kubeadm` generuje PKI, zapisuje static Pody i bootstrapuje kubelet —
  **CNI plugina nie instaluje**
* `NotReady` zaraz po `init` oznacza brak sieci Podów, nie awarię
* certyfikaty klastra są ważne **rok**: `kubeadm certs check-expiration`
* token `join` żyje **24 godziny**

<div data-marpit-fragment>

> Podnoszenie klastra do nowszej wersji omawiamy osobno — w rozdziale
> **Cluster Maintenance**, razem z kopią zapasową i odtwarzaniem etcd.

</div>

<script src="nawigacja.js"></script>
