# linstor-csi-migrator
Convert old LINSTOR flexVolumes to CSI

### How it works

Script takes old PersistentVolumes with Linstor flexVolume driver in Kubernetes and generates commands for update them to use new csi-plugin.

### Preparation

* Make sure that you have `jq` and `kubectl` installed in your system.

* Download the script:

  ```
  curl -LO https://github.com/kvaps/linstor-csi-migrator/raw/master/linstor-csi-migrator.sh
  chmod +x linstor-csi-migrator.sh
  ```

### Usage


* Make sure that you have access to list and modify PVs in your cluster.

* Generate commands:

  ```
  ./linstor-csi-migrator.sh > commands.sh
  ```

* Create backup of your Persistent Volumes:

  ```
  kubectl get pv -o json > pv.json
  ```

* Now you can open `commands.sh` and apply the changes.
