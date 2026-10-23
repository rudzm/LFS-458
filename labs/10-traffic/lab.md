# Lab 10 — wpuść ruch do klastra

**17 punktów obowiązkowych + 3 dodatkowe**

## Cel

Po tym labie umiesz wpuścić ruch z zewnątrz do klastra dwiema drogami i wiesz,
czym się różnią: starszym **Ingressem** (jeden obiekt, reszta w adnotacjach
konkretnego kontrolera) i nowszym **Gateway API** (role rozdzielone między
`Gateway` i `HTTPRoute`, podział ruchu bez żadnej adnotacji).

## Zanim zaczniesz

Kubernetes nie dostarcza ani kontrolera Ingress, ani implementacji Gateway API.
Oba stoją już w tym klastrze — doszły razem ze środowiskiem. Zobacz, co masz,
i uruchom `labctl setup 10`, żeby się upewnić:

```bash
kubectl get ingressclass      # nginx
kubectl get gatewayclass      # klasa od cloud-provider-kind
```

| Co sprawdzasz | Adres |
|---|---|
| Ingress po HTTP | `http://localhost:8080` |
| Ingress po HTTPS | `https://localhost:8443` |
| Gateway API | adres z `status` bramy (zadanie 4) |

Nie musisz ruszać `/etc/hosts` — wystarczy nagłówek `Host`:

```bash
curl -s -H 'Host: sklep.lfs458.local' http://localhost:8080/
```

## Ściągawka

| Chcę | Polecenie |
|---|---|
| stan Ingressów | `kubectl get ingress -n lfs458-m10` |
| zdiagnozować Ingress | `kubectl describe ingress firma -n lfs458-m10` |
| logi kontrolera | `kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50` |
| klasy Ingress | `kubectl get ingressclass` |
| klasy bram | `kubectl get gatewayclass` |
| adres bramy | `kubectl get gateway brama -n lfs458-m10 -o jsonpath='{.status.addresses[0].value}'` |
| stan bramy | `kubectl get gateway,httproute -n lfs458-m10` |
| dlaczego trasa odrzucona | `kubectl describe httproute sklep -n lfs458-m10` |
| certyfikat z Ingressa | `curl -kv -H 'Host: bezpieczny.lfs458.local' https://localhost:8443/ 2>&1 \| grep subject` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Dwie aplikacje za jednym Ingressem, routing po hoście | 4 |
| 2 | Routing po ścieżce z przepisywaniem | 4 |
| 3 | HTTPS z certyfikatem z Secreta — **na osobnym hoście** | 4 |
| 4 | Ten sam routing przez Gateway API | 5 |
| 5 | *(dodatkowe)* podział ruchu 90/10 między wersje | 3 |

## Na co zwrócić uwagę

- **Zadanie 2** — bez `rewrite-target` aplikacja dostaje ścieżkę `/sklep`,
  której nie zna, i zwraca `404`. To najczęstsza pułapka Ingressa.
- **Zadanie 3** — TLS jest na **osobnym hoście** celowo. Po włączeniu TLS
  ingress-nginx zaczyna przekierowywać HTTP na HTTPS (kod `308`) dla tego
  hosta — gdyby to był ten sam host, zepsułbyś sprawdzenia zadania 1.
  Ten efekt uboczny zaskakuje ludzi na produkcji.
- **Zadanie 4** — brama nie wisi na porcie hosta jak Ingress: dostaje własny
  `EXTERNAL-IP` od `cloud-provider-kind`. Adres odczytasz ze statusu obiektu:
  `kubectl get gateway brama -n lfs458-m10 -o jsonpath='{.status.addresses[0].value}'`.
  Na Linuksie jest osiągalny wprost z hosta — to adres z sieci kontenerów kinda.
- Jeśli `kubectl get gateway` pokazuje `PROGRAMMED: False`, kontroler wciąż
  tworzy Pody bramy. Daj mu kilkadziesiąt sekund.

## Sprzątanie

`labctl cleanup 10` usuwa namespace. CRD Gateway API i kontroler **zostają** —
są częścią środowiska, tak jak ingress-nginx. Znikają razem z klastrem
(`labctl env down kind-basic`).
