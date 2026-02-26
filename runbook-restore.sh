#!/bin/bash
set -e

NAMESPACE="pra"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         RUNBOOK DE RESTAURATION PRA — SQLite         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ÉTAPE 1 — Suspension
echo "[ ÉTAPE 1 ] Suspension de l'application..."
kubectl -n $NAMESPACE scale deployment flask --replicas=0
kubectl -n $NAMESPACE patch cronjob sqlite-backup -p '{"spec":{"suspend":true}}'
kubectl -n $NAMESPACE delete job --all --ignore-not-found
echo "  ✔ OK"
echo ""

# ÉTAPE 2 — Liste des backups
echo "[ ÉTAPE 2 ] Backups disponibles :"
echo ""
kubectl -n $NAMESPACE run list-backups --rm -it --quiet --restart=Never \
  --image=alpine \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "list",
        "image": "alpine",
        "command": ["sh","-c","ls -1t /backup/app-*.db 2>/dev/null | xargs -I{} basename {}"],
        "volumeMounts": [{"name":"backup","mountPath":"/backup"}]
      }],
      "volumes": [{"name":"backup","persistentVolumeClaim":{"claimName":"pra-backup"}}]
    }
  }' 2>/dev/null | nl -ba
echo ""

# ÉTAPE 3 — Choix
echo "[ ÉTAPE 3 ] Entrez le nom du fichier à restaurer (ENTRÉE = le plus récent) :"
read -rp "  > " RESTORE_FILE
echo ""

# ÉTAPE 4 — Lancement du job
echo "[ ÉTAPE 4 ] Lancement de la restauration..."
kubectl -n $NAMESPACE delete job sqlite-restore-pitr --ignore-not-found

if [ -z "$RESTORE_FILE" ]; then
  kubectl apply -f pra/50-job-restore-pitr.yaml
else
  # Patch inline de la variable RESTORE_FILE
  sed "s/value: \"\"/value: \"$RESTORE_FILE\"/" pra/50-job-restore-pitr.yaml \
    | kubectl apply -f -
fi

kubectl -n $NAMESPACE wait --for=condition=complete job/sqlite-restore-pitr --timeout=60s
echo "  ✔ Restauration OK"
echo ""

# ÉTAPE 5 — Redémarrage
echo "[ ÉTAPE 5 ] Redémarrage de l'application..."
kubectl -n $NAMESPACE scale deployment flask --replicas=1
kubectl -n $NAMESPACE patch cronjob sqlite-backup -p '{"spec":{"suspend":false}}'
echo "  ✔ Application et CronJob relancés"
echo ""

# ÉTAPE 6 — Vérification
echo "[ ÉTAPE 6 ] Vérification..."
sleep 3
kubectl -n $NAMESPACE get pods
echo ""
echo "→ Lance : kubectl -n pra port-forward svc/flask 8080:80 &"
echo "→ Vérifie : /count et /consultation"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║            RESTAURATION COMPLÈTE ✔                   ║"
echo "╚══════════════════════════════════════════════════════╝"
