---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 11 · Scheduling'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Scheduling

## Rozdział 11 · lab `11`

Kto decyduje, na którym node'ie wyląduje Pod —
i jak na tę decyzję wpłynąć

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — dwie fazy decyzji
2. **Ustawienia schedulera** — czym można pokręcić
3. **Specyfikacja Poda** — `nodeName`, `nodeSelector`, zasoby
4. **Affinity** — warianty `required` i `preferred`
5. **Taints i tolerations** — odpychanie zamiast przyciągania
6. **Lab 11** — pięć mechanizmów rozmieszczania

</div>

---

<!-- _class: sekcja -->

# 1. Jak scheduler podejmuje decyzję

---

# Dwie fazy: filtrowanie i punktowanie

<div data-marpit-fragment>

```text
   wszystkie node'y
        │
        ▼  FILTERING — kto w ogóle może
   [ dość CPU i RAM? pasuje nodeSelector? toleruje taint?
     jest port? jest wolumen? ]
        │
        ▼  SCORING — kto najlepiej
   [ najwięcej wolnych zasobów? affinity? rozproszenie? ]
        │
        ▼
   zapis nodeName w obiekcie Poda
```

</div>

* żaden node nie przeszedł filtrowania → Pod zostaje `Pending`
* decyzja jest **jednorazowa**: raz przypisany Pod nie jest przenoszony

<div data-marpit-fragment>

> Dołożenie node'a nie przeniesie na niego istniejących Podów — od tego
> jest osobne narzędzie (`descheduler`).

</div>

---

# Pod, którego nie da się zaplanować

<div data-marpit-fragment>

```bash
kubectl describe pod za-duzy -n lfs458-m11 | sed -n '/Events/,$p'
```

</div>

<div data-marpit-fragment>

```text
Warning  FailedScheduling  0/3 nodes are available:
  1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: },
  2 Insufficient memory.
```

</div>

<div data-marpit-fragment>

> Ten komunikat jest **najbardziej pomocnym w całym Kubernetesie**: mówi
> dokładnie, ile node'ów odpadło i z jakiego powodu każdy.

</div>

<div data-marpit-fragment>

| Fraza | Znaczenie |
|---|---|
| `Insufficient cpu/memory` | suma `requests` nie mieści się na node'ie |
| `untolerated taint` | brakuje `toleration` |
| `didn't match Pod's node affinity/selector` | etykiety node'a nie pasują |
| `had volume node affinity conflict` | wolumen jest przypięty do innego node'a |

</div>

---

# To requests decyduje, nie zużycie

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `requests`

</div>

* **gwarancja** — tyle Pod dostanie
* **to jest podstawa decyzji** schedulera
* suma requests ≤ pojemność node'a

</div>
<div>

<div data-marpit-fragment>

### `limits`

</div>

* **sufit** — więcej nie weźmie
* CPU: dławienie (throttling)
* pamięć: **OOMKill**
* schedulera nie obchodzą

</div>
</div>

<div data-marpit-fragment>

```yaml
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits:   {memory: 128Mi}
```

</div>

<div data-marpit-fragment>

> Node może być obciążony w 10%, a mimo to **odrzucić** Poda — bo liczy się
> suma zadeklarowanych `requests`, nie faktyczne zużycie. I odwrotnie:
> node bez `requests` przyjmie wszystko, a potem padnie na OOM.

</div>

---

<!-- _class: sekcja -->

# 3. Przypinanie Poda do node'a

---

# Od najprostszego do najbardziej elastycznego

<div data-marpit-fragment>

| Mechanizm | Jak działa | Kiedy |
|---|---|---|
| `nodeName` | **omija schedulera**, wpisujesz node wprost | prawie nigdy |
| `nodeSelector` | prosta równość etykiet | gdy warunek jest jeden |
| `nodeAffinity` | wyrażenia, `required` i `preferred` | gdy potrzebujesz `In`, `NotIn`, preferencji |
| `podAffinity` / `podAntiAffinity` | względem **innych Podów** | kolokacja albo rozproszenie |

</div>

<div data-marpit-fragment>

```bash
kubectl label node lfs458-worker2 dysk=ssd   # potem: nodeSelector: {dysk: ssd}
```

</div>

<div data-marpit-fragment>

> `nodeName` wygląda najprościej i dlatego kusi — ale omija całą logikę
> schedulera: nie sprawdzi zasobów, taintów ani wolumenów.

</div>

---

<!-- _class: sekcja -->

# 4. Affinity

---

# `required` kontra `preferred`

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `required…`

</div>

<div data-marpit-fragment>

```yaml
requiredDuringScheduling
IgnoredDuringExecution:
  - labelSelector:
      matchLabels: {app: api}
    topologyKey: kubernetes.io/hostname
```

</div>

<div data-marpit-fragment>

**warunek** — bez niego Pending

</div>

</div>
<div>

<div data-marpit-fragment>

### `preferred…`

</div>

<div data-marpit-fragment>

```yaml
preferredDuringScheduling
IgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels: {app: api}
      topologyKey: kubernetes.io/hostname
```

</div>

<div data-marpit-fragment>

**punkty** — brak nie blokuje

</div>

</div>
</div>

<div data-marpit-fragment>

> `IgnoredDuringExecution` w obu nazwach znaczy: reguła obowiązuje **przy
> planowaniu**, a nie później. Gdy etykieta node'a zmieni się po starcie,
> działający Pod nie zostanie przeniesiony.

</div>

---

# Pułapka `required` anti-affinity

<div data-marpit-fragment>

```text
   2 worker nodes + 3 repliki + podAntiAffinity typu required
   → trzecia replika zostaje Pending NA ZAWSZE
```

</div>

<div data-marpit-fragment>

Gorzej przy wydaniu nowej wersji:

</div>

<div data-marpit-fragment>

```text
   maxSurge: 1 + anti-affinity required + tyle replik, co node'ów
   → nadmiarowa replika nie ma gdzie stanąć
   → rollout stoi: "1 out of 2 new replicas have been updated"
```

</div>

<div data-marpit-fragment>

> Dlatego w capstone rozproszenie jest zadeklarowane przez **`preferred`**.
> Ta reguła rozproszy repliki tak samo dobrze, gdy jest miejsce,
> a nie zakleszczy wydania, gdy go brakuje.

</div>

<div data-marpit-fragment>

Alternatywa warta poznania: `topologySpreadConstraints` z `maxSkew` —
pozwala powiedzieć „rozproszenie, ale dopuszczam odchylenie o jeden”.

</div>

---

<!-- _class: sekcja -->

# 5. Taints i tolerations

---

# Odwrócenie perspektywy

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Taint — na **node'ie**

</div>

<div data-marpit-fragment>

```bash
kubectl taint node lfs458-worker2 \
  gpu=true:NoSchedule
```

</div>

<div data-marpit-fragment>

*„nie wpuszczam nikogo,
kto się na to nie zgodzi”*

</div>

<div data-marpit-fragment>

| Efekt | Działanie |
|---|---|
| `NoSchedule` | nie wpuszcza nowych |
| `PreferNoSchedule` | unika, ale wpuści |
| `NoExecute` | **wyrzuca** działające |

</div>

</div>
<div>

<div data-marpit-fragment>

### Toleration — w **Podzie**

</div>

<div data-marpit-fragment>

```yaml
tolerations:
  - key: gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

</div>

<div data-marpit-fragment>

*„zgadzam się tam stanąć”*

</div>

</div>
</div>

<div data-marpit-fragment>

> **`toleration` to tylko zgoda, nie przyciąganie.** Pod z wpisem `toleration` może
> wylądować gdziekolwiek indziej. Żeby trafił właśnie tam, potrzebuje
> dodatkowo `nodeSelector` albo `nodeAffinity`.

</div>

---

# Gdzie to spotkasz w praktyce

<div data-marpit-fragment>

```bash
kubectl describe node lfs458-control-plane | grep -i taint
# node-role.kubernetes.io/control-plane:NoSchedule
```

</div>

<div data-marpit-fragment>

| Taint | Kto go nakłada | Po co |
|---|---|---|
| `node-role.kubernetes.io/control-plane` | kubeadm | trzyma workloady z dala od control plane |
| `node.kubernetes.io/not-ready` | kubelet | node nie jest gotowy |
| `node.kubernetes.io/unreachable` | node controller | **`NoExecute`** — eksmisja po 300 s |
| `node.kubernetes.io/disk-pressure` | kubelet | kończy się miejsce |

</div>

<div data-marpit-fragment>

Zdjęcie taintu — to samo polecenie z **minusem** na końcu:

</div>

<div data-marpit-fragment>

```bash
kubectl taint node lfs458-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
```

</div>

---

<!-- _class: lab -->

# Lab 11

<div data-marpit-fragment>

**16 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 11
```

</div>

<div data-marpit-fragment>

Przypniesz Pod etykietą node'a, **celowo utworzysz Pod nie do zaplanowania**
i odczytasz powód ze zdarzeń, rozproszysz repliki anti-affinity `required`,
zarezerwujesz node taintem i trafisz na niego Podem z `toleration`,
a w zadaniu dodatkowym zobaczysz, że preferencja nie blokuje.

</div>

<div data-marpit-fragment>

> Zadanie 2 zostawia Pod w `Pending` **celowo** — to materiał do diagnozy,
> nie awaria.

</div>

---

# Co warto zapamiętać

* scheduler **filtruje**, potem **punktuje**; decyzja jest jednorazowa
* `requests`, nie faktyczne zużycie, decyduje o tym, czy Pod się zmieści
* `kubectl describe pod` podaje dokładny powód niezaplanowania — czytaj go
* `nodeName` omija schedulera i jego zabezpieczenia
* `required` = warunek (ryzyko `Pending`), `preferred` = punkty w rankingu
* anti-affinity `required` przy `maxSurge: 1` potrafi zakleszczyć rollout
* **taint odpycha, toleration tylko się zgadza** — przyciąga `nodeSelector`

<script src="nawigacja.js"></script>
