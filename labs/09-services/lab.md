# Lab 09 — łączenie usług

**17 punktów obowiązkowych + 3 dodatkowe**

## Cel

Spinasz razem wszystko z dnia drugiego: workload dostaje stabilny adres,
nazwę w DNS i drzwi na zewnątrz klastra.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| wystawić Deployment | `kubectl expose deployment web --port=80 --target-port=80 -n lfs458-m09` |
| zobaczyć backendy | `kubectl get endpointslices -n lfs458-m09 -l kubernetes.io/service-name=web` |
| zdiagnozować Service | `kubectl describe svc web -n lfs458-m09` |
| porównać selektor z etykietami | `kubectl get svc web -o jsonpath='{.spec.selector}'` + `kubectl get pods --show-labels` |
| adresy node'ów | `kubectl get nodes -o wide` |
| sprawdzić z hosta | `curl -s <IP-node-a>:30080` |
| rozwiązać nazwę z Poda | `kubectl exec -n lfs458-m09 klient -- nslookup web` |
| zobaczyć konfigurację DNS Poda | `kubectl exec -n lfs458-m09 klient -- cat /etc/resolv.conf` |
| przekierować port lokalnie | `kubectl port-forward -n lfs458-m09 svc/web 8080:80` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Deployment `web` + Service `web` typu ClusterIP | 3 |
| 2 | Service `web-nodeport` na porcie node'a 30080 | 4 |
| 3 | Pod `klient` — dostęp po nazwie krótkiej i po FQDN | 4 |
| 4 | Service headless i różnica w odpowiedzi DNS | 4 |
| 5 | *(dodatkowe)* alias `ExternalName` do usługi spoza klastra | 3 |
| 6 | **Pytania ABCD** — backendy, ClusterIP, typ usługi | 2 |

## Na co zwrócić uwagę

- **Zadanie 1** — pierwsze polecenie przy każdym problemie z Service'em to
  `kubectl get endpointslices`. Puste endpointy oznaczają w 90 % przypadków,
  że selektor nie pasuje do etykiet Podów albo że Pody nie są `Ready`.
- **Zadanie 2** — `kubectl expose` **nie pozwala** wskazać konkretnego
  `nodePort`. Trzeba napisać manifest albo poprawić wygenerowany.
  Node'y Kind to kontenery na mostku dockera — z hosta sięgasz po nie
  wprost pod ich adresem. Sprawdź **każdy** z trzech: port odpowiada
  na wszystkich, nie tylko tam, gdzie stoi Pod.
- **Zadanie 3** — zajrzyj do `/etc/resolv.conf`. Lista `search` tłumaczy,
  dlaczego samo `web` wystarcza, a wpis `options ndots:5` tłumaczy,
  dlaczego zapytania o nazwy zewnętrzne są w Kubernetesie wolniejsze.
- **Zadanie 4** — porównaj `nslookup web` z `nslookup web-headless`.
  Pierwsza odpowiedź to jeden adres wirtualny, druga — trzy adresy Podów.
  Na tym stoi obsługa StatefulSetów.
- Spróbuj też `ping` na ClusterIP. Nie odpowie — bo to nie jest interfejs
  sieciowy, tylko wpis w regułach iptables dla konkretnego portu TCP.

## Sprzątanie

```bash
labctl cleanup 09
```
