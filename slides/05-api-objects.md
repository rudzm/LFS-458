---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 5 · API Objects'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# API Objects

## Rozdział 5 · lab `05`

Katalog obiektów, zasięgi — i RBAC,
czyli kto może zrobić co i gdzie

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Obiekty API** — wspólna budowa, zasięg, właściciele
2. **Grupa v1** — co siedzi w rdzeniu
3. **Zasoby API** — jak je odkrywać bez dokumentacji
4. **RBAC** — cztery obiekty i jedna reguła
5. **ServiceAccount** — `default`, tokeny i co z nimi wolno
6. **Lab 05** — budujesz ServiceAccount z minimalnymi uprawnieniami

</div>

---

<!-- _class: sekcja -->

# 1. Obiekty API

---

# Zasięg: namespace'owany czy klastrowy

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Namespaced

</div>

<div data-marpit-fragment>

Pod, Service, Deployment, Secret,
ConfigMap, Role, RoleBinding,
PersistentVolumeClaim

</div>

<div data-marpit-fragment>

```bash
kubectl api-resources --namespaced=true
```

</div>

</div>
<div>

<div data-marpit-fragment>

### Cluster-scoped

</div>

<div data-marpit-fragment>

Node, PersistentVolume, Namespace,
ClusterRole, ClusterRoleBinding,
StorageClass, CustomResourceDefinition

</div>

<div data-marpit-fragment>

```bash
kubectl api-resources --namespaced=false
```

</div>

</div>
</div>

<div data-marpit-fragment>

> Para do zapamiętania: **PersistentVolume jest klastrowy, a
> PersistentVolumeClaim — namespace'owany**. Wrócimy do niej w rozdziale 8.

</div>

<div data-marpit-fragment>

Namespace **nie jest granicą bezpieczeństwa sieciowego** — to granica nazw
i jednostka, na której ustawia się limity i uprawnienia.

</div>

---

# Właściciele i kasowanie kaskadowe

<div data-marpit-fragment>

```bash
kubectl get pod <nazwa> -o jsonpath='{.metadata.ownerReferences[0].kind}'
```

</div>

<div data-marpit-fragment>

```text
   Deployment  ──owns──►  ReplicaSet  ──owns──►  Pod
```

</div>

* `ownerReferences` buduje **drzewo własności**
* usunięcie właściciela kasuje potomków — tym zajmuje się garbage collector
* `--cascade=orphan` zostawia potomków przy życiu
* zmiana etykiety Poda **wypisuje go** z selektora ReplicaSetu: kontroler
  tworzy nowy, a odcięty działa dalej *(technika diagnostyczna z labu 06)*

<div data-marpit-fragment>

> Dlatego usunięcie namespace'u kasuje wszystko w środku — i dlatego
> `labctl cleanup` to w większości modułów jedno polecenie.

</div>

---

<!-- _class: sekcja -->

# 2. Grupa v1 i katalog zasobów

---

# Gdzie czego szukać

<div data-marpit-fragment>

| Grupa | Co zawiera |
|---|---|
| `v1` *(rdzeń)* | Pod, Service, ConfigMap, Secret, Namespace, Node, PV, PVC |
| `apps/v1` | Deployment, ReplicaSet, StatefulSet, DaemonSet |
| `batch/v1` | Job, CronJob |
| `networking.k8s.io/v1` | Ingress, NetworkPolicy, IngressClass |
| `rbac.authorization.k8s.io/v1` | Role, RoleBinding, ClusterRole, ClusterRoleBinding |
| `policy/v1` | PodDisruptionBudget |
| `storage.k8s.io/v1` | StorageClass, CSIDriver |
| `apiextensions.k8s.io/v1` | CustomResourceDefinition |

</div>

<div data-marpit-fragment>

```bash
kubectl api-resources --api-group=apps
kubectl api-resources | grep -i networkpolic
```

</div>

<div data-marpit-fragment>

*Nie ucz się tego na pamięć — naucz się tych dwóch poleceń.*

</div>

---

# Skróty, które oszczędzają czas

<div data-marpit-fragment>

```bash
kubectl api-resources -o wide | head
```

</div>

<div data-marpit-fragment>

| Pełna nazwa | Skrót | | Pełna nazwa | Skrót |
|---|---|---|---|---|
| `pods` | `po` | | `services` | `svc` |
| `deployments` | `deploy` | | `namespaces` | `ns` |
| `replicasets` | `rs` | | `configmaps` | `cm` |
| `daemonsets` | `ds` | | `persistentvolumeclaims` | `pvc` |
| `statefulsets` | `sts` | | `ingresses` | `ing` |

</div>

<div data-marpit-fragment>

> Na egzaminie CKA skróty i `kubectl explain` są warte więcej niż pamięć
> do składni YAML-a. Liczy się czas.

</div>

---

<!-- _class: sekcja -->

# 3. RBAC

---

# Cztery obiekty, jedna zasada

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Co wolno

</div>

<div data-marpit-fragment>

| Obiekt | Zasięg |
|---|---|
| `Role` | jeden namespace |
| `ClusterRole` | cały klaster |

</div>

<div data-marpit-fragment>

### Komu

</div>

<div data-marpit-fragment>

| Obiekt | Zasięg |
|---|---|
| `RoleBinding` | jeden namespace |
| `ClusterRoleBinding` | cały klaster |

</div>

</div>
<div>

<div data-marpit-fragment>

### Zasada

</div>

<div data-marpit-fragment>

RBAC jest **wyłącznie pozwalający**:

</div>

* domyślnie **nie wolno nic**
* reguły tylko **dodają** uprawnienia
* **nie da się** niczego odebrać
  regułą zabraniającą

<div data-marpit-fragment>

Uprawnienia użytkownika to **suma**
wszystkich pasujących bindingów.

</div>

</div>
</div>

<div data-marpit-fragment>

> Najważniejszy wzorzec w praktyce: **RoleBinding wskazujący na ClusterRole**.
> Używasz gotowej roli (`view`, `edit`), ale obowiązuje ona tylko
> w namespace bindingu.

</div>

---

# Anatomia reguły

<div data-marpit-fragment>

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: podglad-podow, namespace: lfs458-m05}
rules:
  - apiGroups: [""]                      # "" = grupa rdzeniowa!
    resources: ["pods", "pods/log"]      # podzasoby osobno
    verbs: ["get", "list", "watch"]
```

</div>

<div data-marpit-fragment>

| Pole | Pułapka |
|---|---|
| `apiGroups` | rdzeń to `""`, **nie** `v1` i nie `core` |
| `resources` | liczba **mnoga**: `pods`, nie `Pod` |
| `resources` | podzasób to osobny wpis: `pods/log`, `pods/exec` |
| `verbs` | `list` nie implikuje `get` — wymień oba |

</div>

<div data-marpit-fragment>

```bash
kubectl auth can-i get pods --as=system:serviceaccount:lfs458-m05:czytelnik -n lfs458-m05
kubectl auth can-i --list --as=…       # pełna lista uprawnień
```

</div>

---

# ServiceAccount — identity dla workloadów

<div data-marpit-fragment>

```bash
kubectl create serviceaccount czytelnik -n lfs458-m05
kubectl create role podglad-podow --verb=get,list,watch --resource=pods -n lfs458-m05
kubectl create rolebinding czytelnik-podglad \
  --role=podglad-podow --serviceaccount=lfs458-m05:czytelnik -n lfs458-m05
```

</div>

* **użytkownicy** nie są obiektami w Kubernetesie — przychodzą z certyfikatu,
  tokena OIDC albo webhooka
* **ServiceAccount** to identity Poda — i zwykły obiekt w API
* Pod bez wskazanego SA dostaje `default` z namespace'u — który
  **nie ma żadnych uprawnień** i dobrze

<div data-marpit-fragment>

> W `subjects` ServiceAccount **zawsze** wymaga pola `namespace` —
> nawet w ClusterRoleBinding. To częsty powód cichego niedziałania.

</div>

---

# Każdy namespace ma `default`

<div data-marpit-fragment>

```bash
kubectl get sa -A --field-selector metadata.name=default
# NAMESPACE         NAME      NAMESPACE        NAME
# default           default   kube-public      default
# kube-node-lease   default   kube-system      default
```

</div>

<div data-marpit-fragment>

ServiceAccount `default` powstaje **razem z namespace'em** i nie da się go
trwale usunąć — kontroler odtworzy go od razu.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Co dostaje każdy Pod**

</div>

<div data-marpit-fragment>

Token `default` jest montowany
automatycznie, nawet gdy nie
wskażesz żadnego SA.

</div>

</div>
<div>

<div data-marpit-fragment>

**Dlaczego to nie boli**

</div>

<div data-marpit-fragment>

`default` **nie ma żadnych
uprawnień** — uwierzytelni się
w API i usłyszy „nie wolno".

</div>

</div>
</div>

<div data-marpit-fragment>

> Jeśli Pod w ogóle nie potrzebuje API, odetnij mu token:
> `automountServiceAccountToken: false` — w `spec` Poda albo w samym
> ServiceAccouncie. To jedna z pierwszych rzeczy na liście utwardzania.

</div>

---

# Token SA — tym Pod rozmawia z API

<div data-marpit-fragment>

W każdym Podzie, pod `/var/run/secrets/kubernetes.io/serviceaccount/`:

</div>

<div data-marpit-fragment>

```bash
kubectl exec rozmowny -- ls -1 /var/run/secrets/kubernetes.io/serviceaccount/
# ca.crt      ← certyfikat CA klastra, żeby zaufać apiserverowi
# namespace   ← w którym namespace Pod żyje
# token       ← JWT tożsamości tego Poda
```

</div>

<div data-marpit-fragment>

Mając te trzy pliki, Pod rozmawia z API zwykłym `curl`-em:

</div>

<div data-marpit-fragment>

```bash
S=/var/run/secrets/kubernetes.io/serviceaccount
curl -s --cacert $S/ca.crt -H "Authorization: Bearer $(cat $S/token)" \
  https://kubernetes.default.svc/api/v1/namespaces/$(cat $S/namespace)/pods
# { "kind": "PodList", "apiVersion": "v1", … }
```

</div>

<div data-marpit-fragment>

> Tak właśnie działa **każdy** operator i kontroler w klastrze. Nie ma tam
> magii — jest token, CA i HTTP.

</div>

---

# Token to uwierzytelnienie, nie uprawnienia

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Token na żądanie**

</div>

<div data-marpit-fragment>

```bash
kubectl create token czytelnik \
  -n lfs458-m05
```

</div>

<div data-marpit-fragment>

Ważny **godzinę**, związany
z odbiorcą (`aud`), nieodnawialny.
Od Kubernetesa 1.24 ServiceAccount
**nie ma** już stałego Secreta
z tokenem.

</div>

</div>
<div>

<div data-marpit-fragment>

**RBAC decyduje o reszcie**

</div>

<div data-marpit-fragment>

```bash
kubectl auth can-i list pods \
  -n demo \
  --as=system:serviceaccount:demo:default
# no          ← zanim nadasz Role

# yes         ← po RoleBinding
```

</div>

</div>
</div>

<div data-marpit-fragment>

> `sub` w tokenie to `system:serviceaccount:<namespace>:<nazwa>` — dokładnie
> ta nazwa, którą wpisujesz w `--as` i w `subjects` RoleBindingu. Jeśli RBAC
> „nie działa", najpierw sprawdź, czy te trzy zapisy się zgadzają.

</div>

---

<!-- _class: lab -->

# Lab 05

<div data-marpit-fragment>

**13 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 05
```

</div>

<div data-marpit-fragment>

Zbadasz katalog API klastra, a potem zbudujesz ServiceAccount dla workloadu
i nadasz jej **minimalny** zestaw uprawnień: odczyt Podów, potem ich logów,
potem node'ów przez ClusterRole. Po każdym kroku sprawdzisz granice
poleceniem `kubectl auth can-i`.

</div>

<div data-marpit-fragment>

> Zadanie dodatkowe pokazuje najczęstszy wzorzec produkcyjny:
> RoleBinding wskazujący na wbudowaną ClusterRole `view`.

</div>

---

# Co warto zapamiętać

* każdy namespace ma ServiceAccount `default` — bez uprawnień i nie do usunięcia
* token SA to **uwierzytelnienie**; co wolno, rozstrzyga dopiero RBAC
* od 1.24 tokeny są **krótkożyjące**, wydawane na żądanie, bez stałego Secreta
* zasięg obiektu sprawdzasz `kubectl api-resources --namespaced=false`
* PV jest klastrowy, PVC — namespace'owany
* `ownerReferences` buduje drzewo własności i napędza kasowanie kaskadowe
* RBAC **tylko pozwala**; uprawnienia to suma bindingów, nic się nie odejmuje
* grupa rdzeniowa w regule to `""`; podzasoby wymienia się osobno
* `kubectl auth can-i --list --as=…` to najszybszy sposób sprawdzenia uprawnień
* ServiceAccount w `subjects` zawsze z `namespace`

<script src="nawigacja.js"></script>
