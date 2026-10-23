---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 9 · Services'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Services

## Rozdział 9 · lab `09`

Stabilny adres dla czegoś, co ciągle się zmienia

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — po co komu warstwa między klientem a Podami
2. **Typy Service'ów** — ClusterIP, NodePort, LoadBalancer, ExternalName
3. **DNS** — jak nazwa zamienia się w adres
4. **Lab 09** — stabilny adres i diagnoza pustych backendów

</div>

---

# Problem: adres Poda nie jest adresem usługi

<div data-marpit-fragment>

```bash
kubectl get pods -o wide
# sklep-7d4b8-x9k2p   10.244.1.17
# sklep-7d4b8-m3nq8   10.244.2.9
```

</div>

<div data-marpit-fragment>

Adres Poda jest **efemeryczny**: restart, przeniesienie na inny node,
nowa wersja — nowy adres. Nie da się go nikomu podać.

</div>

<div data-marpit-fragment>

Do tego Podów jest zwykle **kilka** i ruch trzeba między nie rozłożyć.
Jedno i drugie rozwiązuje ten sam obiekt — `Service`.

</div>

---

<!-- _class: sekcja -->

# 1. Przegląd

---

# Service to selektor plus stabilny adres

<div data-marpit-fragment>

```yaml
apiVersion: v1
kind: Service
metadata: {name: web, namespace: lfs458-m09}
spec:
  selector: {app: web}        # KOGO wybiera
  ports:
    - port: 80                # na czym słucha Service
      targetPort: 80          # na czym słuchają Pody
```

</div>

<div data-marpit-fragment>

```text
   Service web  ──selektor app=web──►  Pod  Pod  Pod
   ClusterIP 10.96.x.x                 10.244.1.17  .2.9  .1.23
   (stabilny)                          (zmienne)
```

</div>

* `ClusterIP` jest **wirtualny** — nie należy do żadnej karty sieciowej
* ruch do niego przechwytuje `kube-proxy` regułami iptables/IPVS/nftables
* lista aktualnych adresów Podów żyje w obiektach **EndpointSlice**

---

# Pierwsze pytanie przy awarii: czy ma backendy

<div data-marpit-fragment>

```bash
kubectl get endpointslices -n lfs458-m09 -l kubernetes.io/service-name=web
kubectl describe svc web -n lfs458-m09 | grep -i endpoints
```

</div>

<div data-marpit-fragment>

| Co widzisz | Co to znaczy |
|---|---|
| lista adresów | Service działa, szukaj problemu wyżej |
| `Endpoints: <none>` | **selektor nie pasuje** do etykiet Podów |
| są adresy, ale ruch nie dochodzi | port, NetworkPolicy albo aplikacja |

</div>

<div data-marpit-fragment>

> Pod trafia do EndpointSlice dopiero, gdy jest **Ready**. Dlatego
> `readinessProbe` z rozdziału 6 jest jednocześnie mechanizmem
> wypisywania z równoważenia ruchu.

</div>

<div data-marpit-fragment>

To jest dokładnie ta awaria, którą naprawiasz w labie 12 — jedna literka
w selektorze (`app: sklepik` zamiast `app: sklep`).

</div>

---

<!-- _class: sekcja -->

# 2. Typy Service'ów

---

# Cztery typy, rosnący zasięg

<div data-marpit-fragment>

| Typ | Kto się dodzwoni | Uwagi |
|---|---|---|
| **ClusterIP** *(domyślny)* | tylko wnętrze klastra | podstawa wszystkiego |
| **NodePort** | świat, przez port **każdego** node'a | zakres 30000–32767 |
| **LoadBalancer** | świat, przez adres od dostawcy | goły klaster → `<pending>` |
| **ExternalName** | — | czysty alias DNS (CNAME), bez selektora |

</div>

<div data-marpit-fragment>

```yaml
spec:
  type: NodePort
  ports:
    - {port: 80, targetPort: 80, nodePort: 30080}
```

</div>

<div data-marpit-fragment>

> `NodePort` otwiera port na **wszystkich** node'ach, nie tylko tym, na którym
> stoi Pod. `kube-proxy` przekieruje ruch dalej.
> Node'y Kind to kontenery na mostku dockera, więc z linuksowego hosta
> uderzasz **prosto w adres node'a**: `kubectl get nodes -o wide`, a potem
> `curl <IP>:30080`. Odpowiedzą **wszystkie trzy** — także te bez Poda.

</div>

---

# Headless — gdy nie chcesz wirtualnego adresu

<div data-marpit-fragment>

```yaml
spec:
  clusterIP: None        # to jedno pole zmienia wszystko
  selector: {app: web}
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Zwykły ClusterIP**

</div>

<div data-marpit-fragment>

```text
nslookup web
→ 10.96.14.3    (jeden adres)
```

</div>

<div data-marpit-fragment>

ruch równoważy `kube-proxy`

</div>

</div>
<div>

<div data-marpit-fragment>

**Headless**

</div>

<div data-marpit-fragment>

```text
nslookup web-headless
→ 10.244.1.17
→ 10.244.2.9
→ 10.244.1.23
```

</div>

<div data-marpit-fragment>

klient dostaje **wszystkie** adresy

</div>

</div>
</div>

<div data-marpit-fragment>

Po co: StatefulSety (każdy Pod adresowalny z osobna), klienty z własnym
równoważeniem, bazy danych z protokołem klastrowym.

</div>

---

<!-- _class: sekcja -->

# 3. DNS

---

# Nazwy w klastrze

<div data-marpit-fragment>

```text
   <service>.<namespace>.svc.cluster.local
        │          │       │       │
        │          │       │       └── domena klastra
        │          │       └────────── typ zasobu
        │          └────────────────── namespace
        └───────────────────────────── nazwa Service'u
```

</div>

<div data-marpit-fragment>

```bash
kubectl exec -n lfs458-m09 klient -- wget -qO- http://web
kubectl exec -n lfs458-m09 klient -- wget -qO- http://web.lfs458-m09.svc.cluster.local
kubectl exec -n lfs458-m09 klient -- cat /etc/resolv.conf
```

</div>

<div data-marpit-fragment>

```text
search lfs458-m09.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
```

</div>

<div data-marpit-fragment>

> Krótka nazwa działa dzięki liście `search`. **W obrębie namespace'u**
> wystarczy `web`; do innego namespace'u trzeba `web.inny-ns`.

</div>

---

# Gdy DNS zawodzi

<div data-marpit-fragment>

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns      # czy CoreDNS żyje
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl get svc -n kube-system kube-dns                  # zwykle 10.96.0.10
kubectl exec <pod> -- nslookup kubernetes.default        # test od środka
```

</div>

<div data-marpit-fragment>

| Objaw | Najczęstsza przyczyna |
|---|---|
| `bad address` dla każdej nazwy | CoreDNS nie działa albo brak sieci Podów |
| działa FQDN, nie działa krótka nazwa | zły `search` — sprawdź `dnsPolicy` Poda |
| nazwa się rozwiązuje, połączenia brak | to **nie** DNS — szukaj w Service/NetworkPolicy |

</div>

<div data-marpit-fragment>

> `nslookup kubernetes.default` z wnętrza Poda to najszybszy test
> „czy DNS w ogóle żyje”.

</div>

---

<!-- _class: lab -->

# Lab 09

<div data-marpit-fragment>

**17 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 09
```

</div>

<div data-marpit-fragment>

Nadasz workloadowi stabilny adres i sprawdzisz, **czy Service ma backendy**,
otworzysz go na świat przez NodePort (`curl <IP-node-a>:30080`), dosięgniesz
go po nazwie krótkiej i pełnej z wnętrza klastra, porównasz odpowiedzi DNS
dla Service'u zwykłego i headless, a w zadaniu dodatkowym zrobisz alias
`ExternalName` do usługi spoza klastra.

</div>

---

# Co warto zapamiętać

* Service = **selektor** + stabilny adres; backendy żyją w EndpointSlice
* `Endpoints: <none>` oznacza niepasujący selektor — pierwsza rzecz do sprawdzenia
* Pod wchodzi do EndpointSlice dopiero jako **Ready**
* NodePort otwiera port na **wszystkich** node'ach
* `clusterIP: None` → DNS zwraca adresy wszystkich Podów zamiast jednego wirtualnego
* nazwa pełna to `<svc>.<ns>.svc.cluster.local`; krótka działa dzięki `search`
* „nazwa się rozwiązuje, a połączenia nie ma” to **nie** problem DNS

<script src="nawigacja.js"></script>
