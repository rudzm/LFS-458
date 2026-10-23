---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 1 · Basics of Kubernetes'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Basics of Kubernetes

## Rozdział 1 · lab `01`

Czym jest Kubernetes, z czego składa się klaster
i kto za tym wszystkim stoi

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Czym jest Kubernetes** — i czym nie jest
2. **Struktura klastra** — control plane i worker nodes
3. **Adopcja** — gdzie to dziś realnie działa
4. **Zarządzanie projektem i CNCF** — kto decyduje o kierunku
5. **Lab 01** — pierwsze spojrzenie na żywy klaster

</div>

---

<!-- _class: sekcja -->

# 1. Czym jest Kubernetes

---

# Definicja, która coś znaczy

<div data-marpit-fragment>

> Kubernetes to system, któremu opisujesz **desired state** *(stan docelowy)*,
> a on nieprzerwanie doprowadza do niego **actual state** *(stan faktyczny)*.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**To jest Kubernetes**

</div>

* orkiestracja kontenerów
* deklaratywne API
* samonaprawa i skalowanie
* wspólny model dla wielu chmur

</div>
<div>

<div data-marpit-fragment>

**To nie jest Kubernetes**

</div>

* nie buduje obrazów
* nie jest systemem CI/CD
* nie dostarcza gotowych aplikacji
* nie zastąpi monitoringu

</div>
</div>

---

# Reconciliation loop

<div data-marpit-fragment>

*(pętla uzgadniania)* — to samo robi w kółko każdy kontroler:

</div>

<div data-marpit-fragment>

```text
  obserwuj actual state  →  porównaj z desired state
            ↑                             ↓
            └──────── podejmij działanie ─┘
```

</div>

* usuniesz Poda z Deploymentu → **ReplicaSet** odtworzy go w sekundę
* padnie node → node controller oznaczy Pody i stworzy je gdzie indziej
* **nikt nie wydaje poleceń krok po kroku** — opisujesz cel

<div data-marpit-fragment>

*Zobaczysz to na własne oczy w zadaniu 4 laba.*

</div>

---

<!-- _class: sekcja -->

# 2. Struktura klastra

---

# Dwie role maszyn

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Control plane

</div>

* `kube-apiserver` — jedyne wejście do systemu
* `etcd` — magazyn stanu klastra
* `kube-scheduler` — wybiera node dla Poda
* `kube-controller-manager` — reconciliation loops

</div>
<div>

<div data-marpit-fragment>

### Worker node

</div>

* `kubelet` — agent, rozmawia z API
* `kube-proxy` — reguły sieciowe usług
* **container runtime** — uruchamia kontenery
* **CNI plugin** — sieć Podów

</div>
</div>

<div data-marpit-fragment>

> Na klastrze `kubeadm` komponenty control plane działają jako **static Pody** —
> kubelet czyta je z `/etc/kubernetes/manifests`, z pominięciem schedulera.

</div>

---

# Wszystko przez jedno wejście

<div data-marpit-fragment>

```bash
kubectl get pods -v=8 2>&1 | grep -E 'GET|Response Status'
```

</div>

* `kubectl` to **klient HTTP** — nie ma żadnego kanału specjalnego
* komponenty też rozmawiają wyłącznie przez `kube-apiserver`
* `etcd` jest dostępne **tylko** dla apiservera
* wniosek praktyczny: co potrafi `kubectl`, potrafi każdy klient API

---

<!-- _class: sekcja -->

# 3. Adopcja

---

# Gdzie to realnie działa

* standard de facto dla rozwiązań kontenerowych — u wszystkich dużych dostawców
  chmury jako usługa zarządzana (EKS, AKS, GKE) i on-premises
* najczęstsze powody wdrożenia: **jednolity sposób wdrażania**, odporność
  na awarie node'ów, elastyczne wykorzystanie sprzętu
* najczęstsza pułapka: wdrożenie Kubernetesa **bez** zmiany sposobu budowania
  i wydawania aplikacji — wtedy to tylko droższy sposób uruchamiania kontenerów

---

<!-- _class: sekcja -->

# 4. Zarządzanie projektem i CNCF

---

# Kto decyduje o kierunku

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Projekt

</div>

* **SIG-i** (Special Interest Groups) — obszary: sieć, pamięć, API…
* **KEP** — dokument propozycji zmiany; nic nie wchodzi bez niego
* cykl wydawniczy: ok. **3 wydania rocznie**
* wsparcie: ostatnie **3 wydania mniejsze**

</div>
<div>

<div data-marpit-fragment>

### CNCF

</div>

* fundacja pod Linux Foundation
* Kubernetes był jej **pierwszym** projektem (2016)
* prowadzi certyfikacje: **CKA**, CKAD, CKS
* definiuje zgodność: *Certified Kubernetes*

</div>
</div>

<div data-marpit-fragment>

> Praktyczny wniosek: klaster trzeba **aktualizować**. Wersja starsza niż trzy
> wydania nie dostaje już poprawek bezpieczeństwa.

</div>

---

<!-- _class: lab -->

# Lab 01

<div data-marpit-fragment>

**10 punktów + 2 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 01
```

</div>

<div data-marpit-fragment>

Zinwentaryzujesz node'y i komponenty control plane, znajdziesz dodatki
doinstalowane do klastra i **zobaczysz reconciliation loop na żywo** —
usuwając Poda i patrząc, co się stanie.

</div>

---

# Co warto zapamiętać

* Kubernetes doprowadza **actual state** do **desired state** — w kółko, sam
* `kube-apiserver` to jedyne wejście; `etcd` widzi tylko on
* control plane w klastrze `kubeadm` to **static Pody** na node'ie
* między Deploymentem a Podami zawsze stoi **ReplicaSet**
* klaster wymaga utrzymania: wsparcie obejmuje **trzy ostatnie wydania**

<script src="nawigacja.js"></script>
