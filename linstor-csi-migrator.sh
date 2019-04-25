#!/bin/bash
set -eo pipefail

if ! ( [ "$1" = "flexvolume" ] || [ "$1" = "csi1" ] || [ "$1" = "csi2" ] ); then
  echo "USAGE: $(basename $0) <flexvolume|csi1|csi2>"
  exit 1
fi

echo
echo "# Backup everything first"
echo "kubectl get pv -o json > pv.json"
echo

[ "$1" = "flexvolume" ] && \
  kubectl get pv -o json | \
  jq -c '.items[] |
    select(.spec.flexVolume.driver=="linbit/linstor-flexvolume")' | \
  jq -c '.spec.csi={driver: "io.drbd.linstor-csi", fsType: .spec.flexVolume.fsType, volumeHandle: .metadata.name} |
    del(.spec.flexVolume) |
    .metadata.annotations={"pv.kubernetes.io/provisioned-by": "io.drbd.linstor-csi"} |
    .metadata.finalizers=["kubernetes.io/pv-protection", "external-attacher/io-drbd-linstor-csi"] |
    del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' | \
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
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}' &&
kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null &&
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
echo '$VOLUME_JSON' | kubectl create -f -

EOT
done

[ "$1" = "csi1" ] && \
  kubectl get pv -o json | \
  jq -c '.items[] |
    select(.spec.csi.driver=="io.drbd.linstor-csi") |
    select(.spec.csi.volumeHandle |
    test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))' | \
  jq -c '.spec.csi.volumeHandle = "csi-\(.spec.csi.volumeHandle)" |
    del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' | \
  while read VOLUME_JSON; do
    NAME="$(echo "$VOLUME_JSON" | jq -r .metadata.name)"
    LINSOR_NAME="$(echo "$VOLUME_JSON" | jq -r .spec.csi.volumeHandle)"

    cat <<EOT
# PV: $NAME"
linstor rd sp "$LINSOR_NAME" Aux/csi-volume-annotations "\$(linstor rd lp "$LINSOR_NAME" | awk '\$2 == "Aux/csi-volume-annotations" {print \$4}' | sed 's/\\("id" *: *"\\)\\([a-fA-F0-9-]*"\\)/\\1csi-\\2/g')"
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}' &&
kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null &&
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
echo '$VOLUME_JSON' | kubectl create -f -

EOT
done

[ "$1" = "csi2" ] && \
  kubectl get pv -o json | \
  jq -c '.items[] |
    select(.spec.csi.driver=="io.drbd.linstor-csi") |
    select(.spec.csi.volumeHandle |
    test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") | not)' | \
  jq -c 'del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' | \
  sed 's/io.drbd.linstor-csi/linstor.csi.linbit.com/g' | \
  while read VOLUME_JSON; do
    NAME="$(echo "$VOLUME_JSON" | jq -r .metadata.name)"
    LINSOR_NAME="$(echo "$VOLUME_JSON" | jq -r .spec.csi.volumeHandle)"
    PVC_NAME="$(echo "$VOLUME_JSON" | jq -r .spec.claimRef.name)"
    PVC_NAMESPACE="$(echo "$VOLUME_JSON" | jq -r .spec.claimRef.namespace)"

    cat <<EOT
# PV: $NAME"
linstor rd sp "$LINSOR_NAME" Aux/csi-volume-annotations "\$(linstor rd lp "$LINSOR_NAME" | awk '\$2 == "Aux/csi-volume-annotations" {print \$4}' | sed 's/io.drbd.linstor-csi/linstor.csi.linbit.com/g')"
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}' &&
kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null &&
kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
echo '$VOLUME_JSON' | kubectl create -f -
kubectl annotate persistentvolumeclaim -n "$PVC_NAMESPACE" "$PVC_NAME" "volume.beta.kubernetes.io/storage-provisioner=linstor.csi.linbit.com" --overwrite

EOT
done
