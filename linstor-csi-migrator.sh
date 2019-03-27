#!/bin/bash

confirm() {
  while true; do
      read -p "Are you ready? [y/n]: " yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit;;
          * ) echo "Please answer yes or no.";;
      esac
  done
}

DIR="mig/$(date "+%Y.%m.%d-%H-%M-%S")"

mkdir -p "$DIR"

kubectl get pv -o json | tee \
  >(jq -c '.items[] | select(.spec.flexVolume.driver=="linbit/linstor-flexvolume")' > "$DIR/linstor-flexvolumes.json") \
  >(jq -c '.items[] | select(.spec.csi.driver=="io.drbd.linstor-csi") | select(.spec.csi.volumeHandle | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"))' > "$DIR/linstor-old-csi.json") \
  >"$DIR/all.json"

echo
echo "Processing old-style CSI volumes:"
echo
cat "$DIR/linstor-old-csi.json" | jq -r 'select(.metadata.name) | .metadata.name' | sed 's/^/  /g'
echo

 Write the changes
cat "$DIR/linstor-old-csi.json" | jq -c '.spec.csi.volumeHandle = "csi-\(.spec.csi.volumeHandle)"' > "$DIR/linstor-old-csi-repaired.json"

# Control check
OLD_HANDLE="$(cat "$DIR/linstor-old-csi.json" | jq -r .spec.csi.volumeHandle | head -n1)"
NEW_HANDLE="$(cat "$DIR/linstor-old-csi-repaired.json" | jq -r .spec.csi.volumeHandle | head -n1)"

echo "Backup saved in $(readlink -f "$DIR/linstor-old-csi.json" )"
echo "New volumes saved in $(readlink -f "$DIR/linstor-old-csi-repaired.json" )"
echo
echo "For each one we will replace .spec.csi.volumeHandle from \"$OLD_HANDLE\" to \"$NEW_HANDLE\" format"
echo "Please disable Linstor CSI-provisioner before continue!"
echo

confirm
cat "$DIR/linstor-old-csi-repaired.json" | jq -c . | while read VOLUME_JSON; do
  NAME="$(echo "$VOLUME_JSON" | jq -r .metadata.name)"
  echo "$NAME"
  kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
  kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null
  kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
  echo "$VOLUME_JSON" | kubectl create -f -
done


echo
echo "Processing flexvolumes:"
echo
cat "$DIR/linstor-flexvolumes.json" | jq -r 'select(.metadata.name) | .metadata.name' | sed 's/^/  /g'
echo

# Write the changes
cat "$DIR/linstor-flexvolumes.json" | jq '.spec.csi={driver: "io.drbd.linstor-csi", fsType: .spec.flexVolume.fsType, volumeHandle: .metadata.name} | del(.spec.flexVolume) | .metadata.annotations={"pv.kubernetes.io/provisioned-by": "io.drbd.linstor-csi"} | .metadata.finalizers=["kubernetes.io/pv-protection", "external-attacher/io-drbd-linstor-csi"]' > "$DIR/linstor-flexvolumes-repaired.json"

echo "Backup saved in $(readlink -f "$DIR/linstor-flexvolumes.json" )"
echo "New volumes saved in $(readlink -f "$DIR/linstor-flexvolumes-repaired.json" )"
echo
echo "For each one we will replace .spec.flexVolume to .spec.csi section"
echo "Please disable Linstor FlexVolume- and CSI- provisioners before continue!"
echo

confirm
cat "$DIR/linstor-flexvolumes-repaired.json" | jq -c . | while read VOLUME_JSON; do
  NAME="$(echo "$VOLUME_JSON" | jq -r .metadata.name)"
  echo "$NAME"
  kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
  kubectl delete persistentvolume "$NAME" --grace-period=0 --force --wait=false 2>/dev/null
  kubectl patch persistentvolume "$NAME" -p '{"metadata":{"finalizers":null}}'
  echo "$VOLUME_JSON" | kubectl create -f -
done
