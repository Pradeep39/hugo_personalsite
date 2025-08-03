---
title: "Part 2 - Implement File and Block Storage"
date: 2025-01-17
description: Build a personal private cloud with palm sized system on chips (SoCs)
menu:
  sidebar:
    name: Part 2 - File and Block Storage
    identifier: private-cloud-part2
    parent: private-cloud
    weight: 15
tags: ["Basic", "Multi-lingual"]
categories: ["Basic"]
---

In Part 1 of this series, we successfully built a private compute cloud on a palm-sized Raspberry Pi 5 cluster. As we stepped through the setup, we looked at how Kubernetes uses the Container Runtime Interface (CRI) to drive one or more containers per pod. We also examined how the Container Network Interface (CNI) helps provide an overlay network that implements the [Kubernetes network model](https://kubernetes.io/docs/concepts/services-networking/#the-kubernetes-network-model) and provides required intra- and inter-pod networking guarantees. In this part of the series, we focus on the Container Storage Interface (CSI) to add the foundational storage service capabilities that can provide block and file storage.Container Storage Interface started as an initiative to unify the storage interface across various Container orchestrators like Kubernetes, Mesos, Docker Swarm, and Cloud Foundry. For a deeper dive on how Storage providers implement CSI, see [this article](https://portworx.com/knowledge-hub/a-complete-guide-to-kubernetes-csi/). 

When CSI saw adoption in Kubernetes, the volume layer became truly extensible. Using CSI, third-party storage providers could write and deploy plugins exposing new storage systems in Kubernetes without ever having to touch the core Kubernetes layers. CSI gave Kubernetes users more storage options, making the system more secure and reliable. Amongst a few choices, we explore an open-source software, [Longhorn](https://longhorn.io/). The primary consideration for my choice of Longhorn is its lightweight nature, which fits the profile of palm-sized computing. [Ceph](https://ceph.io/en/) or [Portworx](https://portworx.com/) are better choices for production-grade applications. That said, Longhorn is mature and boasts a persistent distributed block storage with built-in incremental snapshots and backup features for Kubernetes. Let's explore how Longhorn can serve block storage and file storage needs. 

### Step 1: Install Helm

Helm is a package manager for Kubernetes. It is analogous to pip in Python programming and allows users to provide, share, and use software built for Kubernetes. Installing Helm is very simple. You may install it from a [script](https://helm.sh/docs/intro/install/#from-script) or through respective [OS package managers](https://helm.sh/docs/intro/install/#through-package-managers) such as Homebrew, apt, or snap.

### Step 2: Install Prerequisites on all Nodes

Internet Small Computer Systems Interface, or iSCSI, is an Internet Protocol-based storage networking standard for linking data storage over a network. We first install or upgrade the open-iscsi package using apt-get. We then verify that the iscsid daemon is running on all the nodes. For help installing open-iscsi, refer to [this section](https://longhorn.io/docs/1.7.2/deploy/install/#installing-open-iscsi) of Longhorn documentation. Another critical step is to load the kernel module iscsi_tcp on all the nodes using the modprobe command below. iSCSI and the iscsi_tcp module enable network access to storage devices over TCP. The NFS client is another dependency that enables ReadWriteMany (RWX) access mode, which is foundational to Elastic File Service on top of block storage. To install all the prerequisites, you may run the following commands on all the nodes.

```
#Install or upgrade iSCSI ( 
sudo apt-get update -y && /
sudo apt-get install open-iscsi

#load kernel module iscsi_tcp to enable ne
sudo modprobe iscsi_tcp

#verify iscsid daemon is running
systemctl status iscsid

# Enable and restart just in case the service is disabled
sudo systemctl enable iscsid
sudo systemctl restart iscsid

#install the nfs client software
sudo apt-get install nfs-common
```

### Step 3: Install Longhorn

Follow the [well-documented instructions](!https://longhorn.io/docs/1.7.2/deploy/install/install-with-helm/#installing-longhorn) at longhorn.io and run referenced helm commands to install the respective Services, Deployments, Daemon sets, and Replica sets in a dedicated Kubernetes namespace. For a brief overview of these Kubernetes Objects, also known as controllers, refer to this [well-written blog](https://semaphoreci.com/blog/replicaset-statefulset-daemonset-deployments). Key things to take away from the referenced reading are the following:

* **Deployment** is a Kuberentes Controller that manages application pods and offers features like rolling updates, rollback, and scaling.
* **Service** is a controller that provides a stable entry point for accessing pods without knowing their specific IP addresses.
* **DaemonSet** is a controller that allows running system daemons or background processes * that need a singleton guarantee, i.e., exactly one instance of a pod on every node in the cluster.
* **ReplicaSet** is a controller that ensures a specific number of identical pods. It is often used by Deployments to manage pod replicas.
* **StatefulSet** is a controller that manages the deployment and scaling of a set of Stateful pods.

After completing the helm instructions in the Longhorn documentation, you can monitor controllers and pods using the command "kubectl get all -n longhorn-system." Alternatively, you may inspect them visually using the Lens tool. Lens is free for personal use and can be downloaded at https://k8slens.dev.

### Step 4: Using the Block Storage

In Kubernetes, Storage provisioning relies on the below foundational building blocks

* **StorageClass** provides a way to implement different quality-of-service levels, backup or any other arbitrary policies. One example of a policy associated with StorageClass is ReclaimPolicy, if ReclaimPolicy is set to delete, all dynamically provisioned volumes will be reclaimed after the pods terminate.
* **Persistent Volumes (PV)** are storage resources provisioned by administrators to provide persistent storage for applications running in pods. These volumes exist independently of the pod lifecycle and can be dynamically provisioned or statically defined. 
* **Persistent Volume Claims (PVC)**, on the other hand, are requests made by applications for storage resources. PVCs abstract away the details of the underlying storage implementation, allowing developers to request storage based on their requirements without needing to know the specifics of how it’s provisioned.

Now that we have both compute and storage fabrics provisioned, it's time to launch our first compute pod with block storage attachment from the private cloud. We summon the compute pod with a simple command "kubectl apply" and a declarative yaml that specifies a manifest for the creation of PVC and a Pod. Note that the storage attachment is expressed as a persistent volume claim (PVC). This can provision the Persistent Volume (PV) dynamically using the default storage class.

If you delete the pod using the command "kubectl delete -f busybox-pod-dynamic-pvc.yaml", the PV and PVC provisioned will be deleted, and the CSI controller will reclaim the storage. Longhorn, by default, provides two storage classes, "longhorn" and "longhorn-static." If you inspect the "kubectl get sc" result, you will observe the ReclaimPoicy set to delete for the storage classes Longhorn (default) and longhorn-static.

```
kubectl apply -f busybox-pod-dynamic-pvc.yaml
```

```
### Save as "busybox-pod-dynamic-pvc.yaml"###
######################################
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
 name: ps2
 namespace: default
spec:
 accessModes:
   - ReadWriteOnce
 resources:
   requests:
     storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-busybox-pod1
  namespace: default
spec:
  containers:
  - image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
    volumeMounts:
      - name: volv
        mountPath: /data
  volumes:
    - name: volv
      persistentVolumeClaim:
        claimName: my-first-pvc
  restartPolicy: Always
```
#### Demo: Dynamic PVC Provisioning Demo using Kubectl and Lens
![Dynamic PVC Provisioning Demo using Kubectl and Lens](/images/content/dynamic_pvc.gif)

### Step 5: Add a custom storage class to realize an elastic file service

With block storage service in place, let's see how we can attach an elastic file storage that can be read and written from multiple pods. To accomplish this, we create a custom storage class with ReclaimPolicy set to "Retain" and "allowVolumeExpansion" set to true to make it elastic. We now use the custom storage class to create a PV that can be attached to multiple pods and live beyond the pod's lifecycle. Custom Storage classes enable you to realize an Elastic File Service on top of the block storage. The command below helps us create a custom storage class by piping the YAML config to stdin.

```
$ cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-efs
provisioner: driver.longhorn.io
parameters:
  dataEngine: v1
  dataLocality: disabled
  disableRevisionCounter: 'true'
  fromBackup: ''
  fsType: ext4
  numberOfReplicas: '3'
  staleReplicaTimeout: '30'
  unmapMarkSnapChainRemoved: ignored
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF
```

### Step 6: Create PV and PVCs using Custom Storage Class

Next, we predefine PV and PVC for the EFS volume, which multiple pods can attach to and share files. We can do this with a simple YAML command, but Longhorn also provides a UI to define the PV. Let's create the EFS volume through the Longhorn UI. Note that when creating volumes for elastic file service, we must select the access mode as "ReadWriteMany." In the below demo, I use [Lens](https://k8slens.dev/) to do port forward for Longhorn UI. You may also choose to forward the port using Kubectl. Refer to [Kubernetes documentation](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/#forward-a-local-port-to-a-port-on-the-pod) if you prefer doing this via the command line.

#### Demo: PV and PVC provisioning for an EFS volume
![Demo: PV and PVC provisioning for an EFS volume](/images/content/pv_pvc.gif)

```### Save as "busybox-multipod-efs-pvc.yaml"###
######################################
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-busybox-pod1
  namespace: default
spec:
  containers:
  - image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
    volumeMounts:
      - name: volv
        mountPath: /data
  volumes:
    - name: volv
      persistentVolumeClaim:
        claimName: efs-pvc
  restartPolicy: Always
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-busybox-pod2
  namespace: default
spec:
  containers:
  - image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
    volumeMounts:
      - name: volv
        mountPath: /data
  volumes:
    - name: volv
      persistentVolumeClaim:
        claimName: efs-pvc
  restartPolicy: Always
```


```
kubectl apply -f busybox-multipod-efs-pvc.yaml
```

After provisioning the pods, we test the EFS file system by downloading the NOAA GHCNd dataset to the EFS mount on the first pod (longhorn-busybox-pod1). We will also check if we can access the data downloaded in pod1 from the second pod(longhorn-busybox-pod2). See the demo below.

#### Demo: EFS volume mounted to multiple pods

![Demo: EFS volume mounted to multiple pods](/images/content/efs_mount.gif)

Congratulations! If you have reached this far and completed the steps above, you should now have your private compute cloud complete with a distributed storage fabric that can help you store your data as files and blocks. In Part 3 of this series, we will focus on realizing an S3-compliant object storage and journey into testing the Data and AI applications on top of our private cloud. Watch this space!
