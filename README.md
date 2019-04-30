# linstor-csi-migrator
Convert old LINSTOR flexVolumes to CSI

### How it works

Script takes PersistentVolumes with Linstor flexVolume driver or old-style CSI metadata, which stopped working after last update of linstor csi-plugin and generates commands for update their metadata to use with new csi-plugin.

* https://github.com/LINBIT/linstor-csi/issues/4 `flexvolume` (migrate flexvolumes to csi)
* https://github.com/LINBIT/linstor-csi/issues/7 `csi1` (migrate csi to use right volume names)
* https://github.com/LINBIT/linstor-csi/issues/11 `csi2` (update csi to use right driver name)

### Preparation

* Make sure that you have `jq` and `kubectl` installed in your system.

* Download the script:

  ```
  curl -LO https://github.com/kvaps/linstor-csi-migrator/raw/master/linstor-csi-migrator.sh
  chmod +x linstor-csi-migrator.sh
  ```

### Usage


* Make sure that you have access to list PVs in your cluster.

* Generate commands:

  ```
  # FlexVolumes:
  ./linstor-csi-migrator.sh flexvolume > flexvolume_commands.sh
  # Old format CSIs:
  ./linstor-csi-migrator.sh csi1 > csi1_commands.sh
  # CSIs with old driver name:
  ./linstor-csi-migrator.sh csi2 > csi2_commands.sh
  ```

* Create backup of your Persistent Volumes:

  ```
  kubectl get pv -o json > pv.json
  ```

* Now you can open `*_commands.sh` and apply the changes.


### Additional steps

* To avoid problems with pods termination, before upgrade `flexvolume` volumes, please stop all the workload.

* During `csi2` upgrade, you should also change drivername for running pods, on every node run:

  ```
  sed -i 's/io.drbd.linstor-csi/linstor.csi.linbit.com/g' `find /var/lib/kubelet/pods/ -mindepth 5 -maxdepth 5 -name vol_data.json`
  ```
