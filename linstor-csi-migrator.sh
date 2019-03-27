#!/bin/bash
set -eo pipefail

echo
echo "# Backup everything first"
echo "kubectl get pv -o json > pv.json"
echo
kubectl get pv -o json | \
  jq -c '.items[] |
    select(.spec.flexVolume.driver=="linbit/linstor-flexvolume")' | \
  jq -c '.spec.csi={driver: "io.drbd.linstor-csi", fsType: .spec.flexVolume.fsType, volumeHandle: .metadata.name} |
    del(.spec.flexVolume) |
    .metadata.annotations={"pv.kubernetes.io/provisioned-by": "io.drbd.linstor-csi"} |
    .metadata.finalizers=["kubernetes.io/pv-protection", "external-attacher/io-drbd-linstor-csi"]' | \
while read VOLUME_JSON; do
  NAME="$(echo "$VOLUME_JSON" | jq -r .metadata.name)"
  CSI_VOLUME_ANNOTATIONS="$(echo "$VOLUME_JSON" | \
    jq -c '.={
      name: .metadata.name,
      id: .metadata.name,
      createdBy: .metadata.annotations."pv.kubernetes.io/provisioned-by",
      creationTime: .metadata.creationTimestamp,
      readonly:false,
      parameters: {}
    }')"


    cat <<EOT
# PV: $NAME"
linstor rd sp "$NAME" 'Aux/csi-volume-annotations' '$CSI_VOLUME_ANNOTATIONS'
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
echo '$VOLUME_JSON' | kubectl create -f -

EOT
done
