#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 13 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m13
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1 i 3: CRD z walidacją, kolumnami i podzasobem status"
cat <<'YAML' | k apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: zadania.lfs458.io
spec:
  group: lfs458.io
  scope: Namespaced
  names:
    plural: zadania
    singular: zadanie
    kind: Zadanie
    shortNames: [zad]
  versions:
    - name: v1
      served: true
      storage: true
      subresources:
        status: {}
      additionalPrinterColumns:
        - {name: Opis, type: string, jsonPath: .spec.opis}
        - {name: Priorytet, type: integer, jsonPath: .spec.priorytet}
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [opis]
              properties:
                opis:      {type: string, minLength: 3}
                priorytet: {type: integer, minimum: 1, maximum: 5, default: 3}
            status:
              type: object
              properties:
                stan: {type: string}
YAML
k wait --for=condition=Established crd/zadania.lfs458.io --timeout=120s

echo "→ zadanie 2: obiekt Zadanie i dowód działania walidacji"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: lfs458.io/v1
kind: Zadanie
metadata:
  name: sprzatanie
  namespace: lfs458-m13
spec:
  opis: Posprzatac po labie
  priorytet: 2
YAML

echo "   próba z priorytetem 9 (serwer ma odmówić):"
cat <<'YAML' | k apply --dry-run=server -f - 2>&1 | tail -2 || true
apiVersion: lfs458.io/v1
kind: Zadanie
metadata:
  name: zle
  namespace: lfs458-m13
spec:
  opis: Test walidacji
  priorytet: 9
YAML

k get zad -n "$NS"

echo "→ zadanie 4: RBAC dla własnego zasobu"
k create serviceaccount operator-zadan -n "$NS" --dry-run=client -o yaml | k apply -f -
k create role zadania-odczyt --verb=get,list,watch --resource=zadania.lfs458.io -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k create rolebinding operator-zadan --role=zadania-odczyt \
  --serviceaccount="${NS}:operator-zadan" -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
SA="system:serviceaccount:${NS}:operator-zadan"
echo "   list zadania   → $(k auth can-i list zadania --as=$SA -n $NS)"
echo "   delete zadania → $(k auth can-i delete zadania --as=$SA -n $NS)"

echo "→ zadanie 5 (dodatkowe): API agregowane"
k get apiservices 2>/dev/null | grep -v Local | head -3 || true
echo "   odpowiedzi do pytań w labctl lab:"
echo "     apiservice: v1beta1.metrics.k8s.io"
echo "     usluga: metrics-server"
echo "     namespace usługi: kube-system"
echo "     roznica: etcd"

echo
echo "Gotowe. Weryfikacja: labctl check 13"
