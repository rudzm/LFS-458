---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 10 · Advanced Traffic Management'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Advanced Traffic Management

## Rozdział 10 · lab `10`

Ingress, service mesh i Gateway API —
trzy warstwy nad Service'em

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — czego brakuje Service'om
2. **Kontroler Ingress** — i dlaczego sam obiekt nic nie robi
3. **Reguły Ingressa** — host, ścieżka, TLS
4. **Service mesh** — co dokłada i czym płacisz
5. **Ograniczenia Ingressa** — dlaczego powstało Gateway API
6. **Gateway API** — role rozdzielone na trzy obiekty
7. **Lab 10** — ten sam routing dwiema drogami

</div>

---

<!-- _class: sekcja -->

# 1. Czego brakuje Service'om

---

# NodePort i LoadBalancer nie skalują się organizacyjnie

<div data-marpit-fragment>

| Potrzeba | Service to potrafi? |
|---|---|
| jeden adres, wiele aplikacji | nie — każdy Service to osobny port lub LB |
| routing po **nazwie hosta** | nie |
| routing po **ścieżce URL** | nie |
| terminacja **TLS** | nie |
| podział ruchu 90/10 między wersje | nie |

</div>

<div data-marpit-fragment>

Trzydzieści usług = trzydzieści load balancerów u dostawcy.
Albo trzydzieści portów do zapamiętania.

</div>

<div data-marpit-fragment>

> Potrzebny jest **reverse proxy w klastrze**, który rozdziela ruch
> na podstawie zawartości żądania HTTP — czyli warstwy 7.

</div>

---

<!-- _class: sekcja -->

# 2. Kontroler Ingress

---

# Obiekt bez kontrolera nic nie robi

<div data-marpit-fragment>

```text
   Ingress (obiekt w API)     ← to tylko deklaracja
            │
            ▼ obserwuje
   kontroler Ingress (Pod)    ← to wykonuje pracę
            │
            ▼ konfiguruje
   nginx / HAProxy / Envoy / Traefik
```

</div>

* Kubernetes **nie dostarcza** żadnego kontrolera Ingress
* bez niego obiekt `Ingress` zostaje z pustą kolumną `ADDRESS`
* `ingressClassName` wskazuje, **który** kontroler ma go obsłużyć

---

# Który kontroler masz w klastrze

<div data-marpit-fragment>

```bash
kubectl get ingressclass           # jakie klasy są dostępne
kubectl get pods -n ingress-nginx  # czy kontroler w ogóle stoi
```

</div>

<div data-marpit-fragment>

Obiekt `Ingress` bez pasującego kontrolera wygląda jak utworzony poprawnie —
`kubectl get ingress` go pokazuje, API go przyjęło, nic nie protestuje.
Po prostu **nikt go nie realizuje**.

</div>

<div data-marpit-fragment>

> Najczęstsza przyczyna „Ingress nie działa”: brak `ingressClassName`
> albo kontroler stojący na node'ie bez mapowania portów.

</div>

---

<!-- _class: sekcja -->

# 3. Reguły

---

# Routing po hoście

<div data-marpit-fragment>

```yaml
spec:
  ingressClassName: nginx
  rules:
    - host: sklep.lfs458.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: sklep, port: {number: 5678}}}
    - host: blog.lfs458.local
      http:
        paths: [...]
```

</div>

<div data-marpit-fragment>

```bash
curl -s -H 'Host: sklep.lfs458.local' http://localhost:8080/
```

</div>

<div data-marpit-fragment>

> Nie trzeba ruszać `/etc/hosts` — wystarczy nagłówek `Host`.
> To ten sam mechanizm, którego używa przeglądarka po rozwiązaniu nazwy.

</div>

---

# Routing po ścieżce — i pułapka

<div data-marpit-fragment>

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - host: firma.lfs458.local
      http:
        paths:
          - path: /sklep(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: sklep, port: {number: 5678}}}
```

</div>

<div data-marpit-fragment>

> Bez przepisania ścieżki aplikacja dostanie `/sklep` i zwróci **404** —
> bo zna tylko `/`. To najczęstsza pułapka Ingressa.

</div>

---

# `pathType` — trzy tryby dopasowania

<div data-marpit-fragment>

| `pathType` | Zachowanie |
|---|---|
| `Prefix` | dopasowanie po segmentach ścieżki, dosłowne |
| `Exact` | dokładnie ta ścieżka |
| `ImplementationSpecific` | zależy od kontrolera — tu: **wyrażenia regularne** |

</div>

<div data-marpit-fragment>

> Składnia przepisania jest **specyficzna dla kontrolera**. `rewrite-target`
> z `/$2` zadziała na ingress-nginx i na niczym innym — to dokładnie ten
> problem, który rozwiązuje Gateway API.

</div>

---

# TLS

<div data-marpit-fragment>

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=bezpieczny.lfs458.local"

kubectl create secret tls sklep-tls --cert=/tmp/tls.crt --key=/tmp/tls.key -n lfs458-m10
```

</div>

<div data-marpit-fragment>

```yaml
spec:
  tls:
    - hosts: [bezpieczny.lfs458.local]
      secretName: sklep-tls
```

</div>

* Secret musi być typu `kubernetes.io/tls` i leżeć w **tym samym namespace**
* na produkcji certyfikaty wystawia **cert-manager** z Let's Encrypt

<div data-marpit-fragment>

> Efekt uboczny, który zaskakuje: po włączeniu TLS ingress-nginx zaczyna
> przekierowywać HTTP na HTTPS kodem **308** dla tego hosta. Jeśli używałeś
> tego hosta po HTTP — właśnie przestał działać.

</div>

---

<!-- _class: sekcja -->

# 4. Service mesh

---

# Sidecar przejmuje ruch Poda

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Co dokłada

</div>

* **mTLS** między wszystkimi usługami
* retry, timeout, circuit breaking
* podział ruchu po wersjach
* metryki i tracing bez zmian w kodzie
* polityki dostępu na poziomie L7

</div>
<div>

<div data-marpit-fragment>

### Czym płacisz

</div>

* proxy obok **każdego** Poda
  (CPU, RAM, opóźnienie)
* osobna płaszczyzna sterowania
* trudniejsza diagnoza — doszła
  warstwa, która może zawieść

</div>
</div>

<div data-marpit-fragment>

Implementacje: **Istio**, **Linkerd**, **Cilium Service Mesh**
(bez sidecara, w eBPF).

</div>

<div data-marpit-fragment>

> Reguła praktyczna: mesh rozwiązuje problemy, które pojawiają się przy
> **kilkudziesięciu** usługach. Przy pięciu dokłada więcej złożoności,
> niż usuwa.

</div>

---

<!-- _class: sekcja -->

# 5. Ograniczenia Ingressa

---

# Dlaczego powstało coś nowego

<div data-marpit-fragment>

| Ograniczenie | Konsekwencja |
|---|---|
| API opisuje tylko **HTTP/HTTPS** | TCP, UDP i gRPC — przez adnotacje albo wcale |
| wszystko ponad podstawy to **adnotacje** | nieprzenośne między kontrolerami |
| jeden obiekt, jedna rola | deweloper i administrator sieci edytują **ten sam** zasób |
| brak podziału ruchu w API | `canary deployment` przez adnotacje |

</div>

<div data-marpit-fragment>

```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$2
nginx.ingress.kubernetes.io/canary-weight: "10"
```

</div>

<div data-marpit-fragment>

> Te dwie linie **nie zadziałają** na Traefiku ani na HAProxy.
> Ingress stał się standardem, którego rozszerzenia nie są standardem.
>
> *`canary deployment` — wypuszczenie nowej wersji na ułamek ruchu, zanim
> dostanie go całość.*

</div>

---

<!-- _class: sekcja -->

# 6. Gateway API

---

# Trzy obiekty, trzy role

<div data-marpit-fragment>

```text
   GatewayClass     ← administrator klastra: jaka implementacja
        ▲
   Gateway          ← operator platformy: porty, TLS, kto może wpinać trasy
        ▲
   HTTPRoute        ← deweloper: reguły mojej aplikacji
```

</div>

<div data-marpit-fragment>

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: brama, namespace: lfs458-m10}
spec:
  gatewayClassName: cloud-provider-kind
  listeners:
    - {name: http, protocol: HTTP, port: 80,
       allowedRoutes: {namespaces: {from: Same}}}
```

</div>

<div data-marpit-fragment>

> Podział na trzy obiekty to nie komplikacja dla samej komplikacji —
> to odzwierciedlenie tego, że **trzy różne osoby** odpowiadają za te trzy
> warstwy i nie powinny edytować jednego pliku.

</div>

---

# To, co w Ingressie wymagało adnotacji

<div data-marpit-fragment>

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  parentRefs: [{name: brama}]
  hostnames: ["sklep.lfs458.local"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs:
        - {name: sklep,    port: 5678, weight: 90}
        - {name: sklep-v2, port: 5678, weight: 10}
```

</div>

<div data-marpit-fragment>

**`canary deployment` 90/10 — w API, nie w adnotacji.** Zadziała na każdej
zgodnej implementacji.

</div>

<div data-marpit-fragment>

| Gateway API ma w standardzie | Ingress |
|---|---|
| podział ruchu wagami, nagłówki, przepisania | adnotacje kontrolera |
| TCPRoute, UDPRoute, GRPCRoute | nie obsługiwał |

</div>

---

# Stan rzeczy

* Gateway API to **CRD plus kontroler** — Kubernetes nie ma ani jednego
  z nich w standardzie
* implementacje: Envoy Gateway, Istio, Cilium, NGINX Gateway Fabric,
  `cloud-provider-kind` *(tej używamy w labie)*
* Ingress **nie jest porzucony** — działa i będzie działał
* nowe wdrożenia warto zaczynać od Gateway API

<div data-marpit-fragment>

```bash
kubectl get gatewayclass
kubectl get gateway,httproute -n lfs458-m10
kubectl get gateway brama -n lfs458-m10 -o jsonpath='{.status.addresses[0].value}'
```

</div>

<div data-marpit-fragment>

> Różnica widoczna gołym okiem: brama dostaje **własny adres**, a nie port
> na node'ie. Tak samo zachowuje się u dostawcy chmurowego.

</div>

---

<!-- _class: lab -->

# Lab 10

<div data-marpit-fragment>

**17 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 10
```

</div>

<div data-marpit-fragment>

Wystawisz dwie aplikacje przez jeden Ingress — raz po nazwie hosta, raz
po ścieżce z przepisaniem — dołożysz TLS na osobnym hoście, a potem
**zbudujesz tę samą drogę jeszcze raz przez Gateway API** i podzielisz
ruch 90/10 między dwie wersje.

</div>

<div data-marpit-fragment>

| Co | Adres |
|---|---|
| Ingress HTTP / HTTPS | `localhost:8080` / `localhost:8443` |
| Gateway API | adres ze `status` bramy |

</div>

---

# Co warto zapamiętać

* obiekt `Ingress` bez kontrolera **nie robi nic**; `ingressClassName` wskazuje który
* `Prefix` dopasowuje dosłownie — przepisanie ścieżki wymaga adnotacji kontrolera
* włączenie TLS uruchamia przekierowanie **308** na tym hoście
* service mesh daje mTLS i obserwowalność, kosztem proxy przy każdym Podzie
* Ingress jest niestandaryzowany **poza podstawami** — stąd Gateway API
* Gateway API rozdziela role: GatewayClass / Gateway / HTTPRoute
* podział ruchu wagami jest w **API**, nie w adnotacji

<script src="nawigacja.js"></script>
