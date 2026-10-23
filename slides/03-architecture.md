---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 3 · Kubernetes Architecture'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Kubernetes Architecture

## Rozdział 3 · lab `03`

Co dokładnie robi każdy komponent,
jak adresowana jest sieć i co jeszcze działa w klastrze

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Komponenty** — kto z kim rozmawia i w którą stronę
2. **Sieć** — cztery problemy, które Kubernetes musi rozwiązać
3. **Pozostałe systemy klastra** — DNS, metryki, Ingress, CNI plugin
4. **Lab 03** — zaglądasz do środka node'a

</div>

---

<!-- _class: sekcja -->

# 1. Komponenty

---

# Kierunek rozmowy ma znaczenie

<div data-marpit-fragment>

```text
                 ┌──────────────┐
    kubectl ───► │              │ ◄─── kube-scheduler
                 │ kube-api     │ ◄─── kube-controller-manager
    kubelet ───► │   server     │ ◄─── kube-proxy
                 │              │
                 └──────┬───────┘
                        │  tylko apiserver
                        ▼
                     ┌──────┐
                     │ etcd │
                     └──────┘
```

</div>

* **wszystko** idzie przez `kube-apiserver` — nie ma kanałów bocznych
* `etcd` jest dostępne **wyłącznie** dla apiservera
* komponenty **nie rozmawiają ze sobą** bezpośrednio: komunikują się,
  zmieniając obiekty w API i obserwując zmiany

---

# Kto za co odpowiada

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Control plane

</div>

<div data-marpit-fragment>

| Komponent | Rola |
|---|---|
| `kube-apiserver` | brama, walidacja, autoryzacja |
| `etcd` | magazyn stanu, klucz-wartość |
| `kube-scheduler` | **wybiera node** dla Poda |
| `kube-controller-manager` | reconciliation loops |
| `cloud-controller-manager` | integracja z dostawcą |

</div>

</div>
<div>

<div data-marpit-fragment>

### Worker node

</div>

<div data-marpit-fragment>

| Komponent | Rola |
|---|---|
| `kubelet` | uruchamia i pilnuje Podów |
| `kube-proxy` | reguły dla Service'ów |
| container runtime | faktycznie startuje kontenery |
| CNI plugin | adresy i routing Podów |

</div>

</div>
</div>

<div data-marpit-fragment>

> `kube-scheduler` **nie uruchamia** niczego — zapisuje tylko `nodeName`
> w obiekcie Poda. Resztę robi kubelet na wskazanym node'ie.

</div>

---

# Jak powstaje Pod — sześć kroków

<div data-marpit-fragment>

1. `kubectl` wysyła **POST** na `/api/v1/namespaces/<ns>/pods`
2. apiserver: uwierzytelnia → autoryzuje → przepuszcza przez **admission** →
   waliduje → zapisuje do `etcd`
3. **scheduler** widzi Pod bez `nodeName`, filtruje i punktuje node'y,
   zapisuje wybór
4. **kubelet** na tym node'ie widzi Pod przypisany do siebie
5. kubelet woła **CRI**: pobierz obraz, utwórz sandbox, uruchom kontenery
6. kubelet raportuje `status` z powrotem do API

</div>

<div data-marpit-fragment>

> Nikt nikomu nie wydał polecenia. Każdy krok to **reakcja na zmianę stanu
> w API** — to jest reconciliation loop w akcji.

</div>

---

<!-- _class: sekcja -->

# 2. Sieć

---

# Cztery problemy sieciowe

<div data-marpit-fragment>

| Problem | Rozwiązanie |
|---|---|
| kontener ↔ kontener w jednym Podzie | wspólny namespace sieciowy — `localhost` |
| **Pod ↔ Pod** między node'ami | CNI plugin |
| Pod ↔ Service | `kube-proxy` + reguły iptables/IPVS/nftables |
| świat ↔ Service | NodePort, LoadBalancer, Ingress, Gateway API |

</div>

<div data-marpit-fragment>

Model wymaga, żeby **każdy Pod widział każdego innego bez NAT-u** —
to warunek, który musi spełnić każda implementacja CNI.

</div>

<div data-marpit-fragment>

```bash
kubectl get nodes -o custom-columns=WEZEL:.metadata.name,CIDR:.spec.podCIDR
```

</div>

<div data-marpit-fragment>

Pula klastra (`/16`) jest krojona przez controller-manager na **wycinki `/24`**
— po jednym na node. Numer wycinka zależy od kolejności rejestracji node'ów.

</div>

---

# Pod ma jeden adres, nie kontener

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Wewnątrz Poda**

</div>

* jeden adres IP
* wspólny `localhost`
* wspólne porty — **nie mogą
  się dublować**
* opcjonalnie wspólne wolumeny

</div>
<div>

<div data-marpit-fragment>

**Namespace trzyma kontener `pause`**

</div>

* startuje **pierwszy**, przed
  kontenerami aplikacji
* to **w jego** namespace'ie CNI
  plugin nadaje adres IP
* pozostałe kontenery **dołączają**
  do tego namespace'u
* żyje przez cały czas życia Poda —
  dlatego **Pod nie traci adresu IP**,
  gdy aplikacja się restartuje

</div>
</div>

<div data-marpit-fragment>

> Między **osobnymi** Podami `localhost` nie zadziała nigdy — nawet gdy
> stoją na tym samym node'ie. To najkrótsza definicja różnicy między
> Podem a kontenerem.

</div>

---

# Zobaczmy to na żywo

<div data-marpit-fragment>

Trzy kontenery, dwa nasłuchują na **różnych portach**, trzeci ma `wget`:

</div>

<div data-marpit-fragment>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: trzy-porty}
spec:
  containers:
    - {name: alfa,  image: hashicorp/http-echo:1.0, args: ["-text=jestem alfa", "-listen=:5001"]}
    - {name: beta,  image: hashicorp/http-echo:1.0, args: ["-text=jestem beta", "-listen=:5002"]}
    - {name: narzedzia, image: busybox:1.36, command: ["sleep", "3600"]}
EOF
```

</div>

<div data-marpit-fragment>

```bash
kubectl get pod trzy-porty -o wide
# trzy-porty   3/3   Running   0   12s   10.244.2.2   lfs458-worker
```

</div>

<div data-marpit-fragment>

**Trzy kontenery, jeden adres.** Teraz zapytajmy z jednego o pozostałe:

</div>

---

# `localhost` spina kontenery, nie Pody

<div data-marpit-fragment>

```bash
kubectl exec trzy-porty -c narzedzia -- wget -qO- http://localhost:5001
# jestem alfa
kubectl exec trzy-porty -c narzedzia -- wget -qO- http://localhost:5002
# jestem beta

kubectl exec trzy-porty -c narzedzia -- ip -4 addr show eth0 | grep inet
#     inet 10.244.2.2/24 brd 10.244.2.255 scope global eth0
```

</div>

<div data-marpit-fragment>

`narzedzia` nie zna adresu `alfy` ani `bety` — i nie musi. Wszystkie trzy
siedzą w namespace'ie sieciowym kontenera `pause`, więc **dla nich
`localhost` to ten sam stos sieciowy**. Adres widziany w środku jest
dokładnie tym, który `kubectl get pod` pokazuje na zewnątrz.

</div>

<div data-marpit-fragment>

> Gdyby `alfa` i `beta` były osobnymi Podami, to samo `wget` dostałoby
> `Connection refused` — i żadne ustawienie by tego nie zmieniło.

</div>

---

# Druga strona medalu: wspólne porty

<div data-marpit-fragment>

Skoro stos sieciowy jest jeden, to i **porty są wspólne**. Weź poprzedni
manifest i daj obu kontenerom ten sam `-listen`:

</div>

<div data-marpit-fragment>

```yaml
    - {name: pierwszy, image: hashicorp/http-echo:1.0, args: ["-listen=:5001"]}
    - {name: drugi,    image: hashicorp/http-echo:1.0, args: ["-listen=:5001"]}
```

</div>

<div data-marpit-fragment>

```bash
kubectl get pod kolizja
# kolizja   1/2   Error   2 (26s ago)   31s

kubectl logs kolizja -c drugi
# [ERR] server exited with: listen tcp :5001: bind: address already in use
```

</div>

<div data-marpit-fragment>

**`1/2` i zwykły błąd bindowania** — nie magia Kubernetesa, tylko Linux.
Ten sam komunikat dostaniesz, uruchamiając dwa procesy na jednym porcie
na własnym laptopie.

</div>

<div data-marpit-fragment>

```bash
kubectl delete pod trzy-porty kolizja     # sprzątanie po demo
```

</div>

---

<!-- _class: sekcja -->

# 3. Pozostałe systemy klastra

---

# Czego Kubernetes nie ma w pudełku

<div data-marpit-fragment>

| Czego brakuje | Kto to dostarcza | Jak sprawdzić |
|---|---|---|
| sieć Podów | **CNI plugin**: Calico, Cilium, Flannel, kindnet | `kubectl get ds -n kube-system` |
| DNS wewnątrz klastra | **CoreDNS** (Service `kube-dns`) | `kubectl get svc -n kube-system kube-dns` |
| metryki do `kubectl top` i HPA | **metrics-server** | `kubectl top nodes` |
| wejście HTTP z zewnątrz | **kontroler Ingress** | `kubectl get ingressclass` |
| Gateway API | CRD + kontroler | `kubectl get gatewayclass` |
| pamięć trwała | sterownik **CSI** | `kubectl get storageclass` |

</div>

<div data-marpit-fragment>

> To są **dodatki**, nie części Kubernetesa. Dlatego dwa klastry „z tą samą
> wersją” potrafią zachowywać się zupełnie inaczej.

</div>

---

# Static Pody — wyjątek od reguły

<div data-marpit-fragment>

Kubelet uruchamia nie tylko to, co dostanie z API. Czyta też katalog na dysku:

</div>

<div data-marpit-fragment>

```bash
docker exec lfs458-worker grep staticPodPath /var/lib/kubelet/config.yaml
# staticPodPath: /etc/kubernetes/manifests
```

</div>

* plik w tym katalogu → kubelet uruchamia Pod **z pominięciem schedulera**
* w API pojawia się **mirror pod** — kopia tylko do odczytu
* `ownerReferences` wskazuje **Node**, nie kontroler
* `kubectl delete` taki Pod? Wróci w kilka sekund

<div data-marpit-fragment>

> Tak właśnie działa control plane na klastrze `kubeadm`. I dlatego apiserver
> może wystartować, zanim istnieje jakiekolwiek API do odpytania.

</div>

---

<!-- _class: lab -->

# Lab 03

<div data-marpit-fragment>

**14 punktów + 2 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 03
```

</div>

<div data-marpit-fragment>

Zinwentaryzujesz sieć klastra (CNI plugin, pule adresów, DNS, tryb
`kube-proxy`), udowodnisz, że kontenery w jednym Podzie dzielą `localhost`,
i **utworzysz Pod z pominięciem API** — wpisując manifest na node.

</div>

<div data-marpit-fragment>

> Node klastra Kind to zwykły kontener:
> `docker exec -it lfs458-worker bash`

</div>

---

# Co warto zapamiętać

* wszystko idzie przez `kube-apiserver`; `etcd` widzi **tylko on**
* komponenty nie rozmawiają ze sobą — reagują na zmiany obiektów w API
* scheduler **wybiera** node, kubelet **uruchamia**
* każdy Pod ma jeden adres; `localhost` działa tylko wewnątrz Poda
* pula `/16` klastra jest krojona na wycinki `/24` per node
* sieć, DNS, metryki i Ingress to **dodatki** — klaster bez nich też „działa”
* static Pod należy do node'a, nie do kontrolera — i wraca po usunięciu

<script src="nawigacja.js"></script>
