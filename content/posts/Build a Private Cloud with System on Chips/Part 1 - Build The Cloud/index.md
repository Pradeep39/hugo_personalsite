---
title: "Part 1 - Build the Cloud"
date: 2025-01-10
description: Build a personal private cloud with palm sized system on chips (SoCs)
menu:
  sidebar:
    name: Part 1 - Build the Cloud
    identifier: private-cloud-part1
    parent: private-cloud
    weight: 14
tags: ["Basic", "Multi-lingual"]
categories: ["Basic"]
---
According to a [Cloud Native Computing Foundation (CNCF) report](https://www.cncf.io/reports/kubernetes-project-journey-report/), Kubernetes is the second largest open-source project in the world after Linux and the primary container orchestration tool for 71% of Fortune 100 companies. During the winter break of 2024, my passion for palm-sized computing blended with my apprehensions about diving deep into the world of Kubernetes (k8s), culminating in an unexpected yet worthwhile endeavor to build a private cloud, complete with a compute cloud fabric, distributed block/file storage, and an S3-compliant distributed object storage. These foundational cloud primitives resembling EC2, EBS, and EFS services in the AWS cloud have the potential to enable compute/io intensive ML & Data Engineering workloads using a modern lakehouse architecture with Spark, Iceberg, Jupyter, and Trino on Kubernetes (k8s). In a subsequent part of this series, we will put this stack to test by processing a real-world Global Historical Climatology Network Daily (GHCNd) dataset, which contains daily climate data from land surface stations across the globe dating back to the 1900s. [National Oceanic and Atmospheric Administration (NOAA)](https://www.noaa.gov/) publicly makes this dataset available.

### Step 1: Procure the SoCs
You need the items below to emulate and follow my learning trail. You may procure these from any authorized Raspberry Pi reseller.

* [Raspberry Pi single board with 8GB RAM and a 64-bit quad-core Arm-based processor ( $80 each, 3-5 count )](https://www.raspberrypi.com/products/raspberry-pi-5/)
* [Raspberry Pi Active Cooler ( $5 each, 3-5 count )](https://www.raspberrypi.com/products/active-cooler/)
* [Raspberry Pi 256 GB NVMe SSD kit with a Hat ($40; 3-5 count)](https://www.raspberrypi.com/products/ssd-kit/)
* [Raspberry Pi 27W USB-C Power Supply rated at 5A/5V ($12; 3-5 count)](https://www.raspberrypi.com/products/27w-power-supply/)
* [A minimum of 128 GB micro SD card with speed class: C10, U3, V30, A2 or higher
Layered Acrylic Cluster case for Raspberry Pi ( 2 )](https://www.amazon.com/dp/B085XT8W9S/ref=dp_iou_view_item?ie=UTF8&th=1)
---

**Get a dedicated official Raspberry Pi 5 27W power supply, as other third-party power supplies may not deliver the desired amps and volts.

---

With the above, you are considering a total build cost of $481 for three units (minimum build) and $775 for five units (preferred build) before taxes. If you wish to skip building the cluster and emulate using a Kind cluster locally on your Mac or PC, note that Kind on Mac cannot meet the networking prerequisites to enable storage services. Perhaps "Kind on Linux" may work, but I'm yet to test it.

### Step 2: Imaging the micro SD cards with Ubuntu 64 bit Server edition

Thanks to the official [Raspberry Pi Imager](https://www.raspberrypi.com/software/), it now only takes a few minutes to unbox and install Raspberry Pi with a bootable micro SD card. When baking the image, choose the Ubuntu server edition, enter the wifi password, and designate the hostnames for control planes and workers. I chose the names cplane for my control plane and worker1, worker2, worker3, and worker4 for the remaining four nodes. For simplicity, I recommend using networking over wifi. Additionally, you may reserve IP addresses for these hosts. I use a Google router and was able to add DHCP reservations from the Google Home app. Refer to your router documentation for instructions.

### Step 3: Setup the SSD Kit & Active Cooler

The Raspberry Pi SSD Kit bundles a [Raspberry Pi M.2 HAT+](https://www.raspberrypi.com/documentation/accessories/m2-hat-plus.html) with a [Raspberry Pi SSD](https://www.raspberrypi.com/documentation/accessories/ssds.html) and includes a 16mm stacking header, spacers, and screws to enable fitting on Raspberry Pi 5. The M.2 HAT+ can be alongside the tiny Raspberry Pi Active Cooler, which keeps the cluster cool despite its form factor. To install the Raspberry Pi SSD Kit, follow the [installation instructions for the Raspberry Pi M.2 HAT+](https://www.raspberrypi.com/documentation/accessories/m2-hat-plus.html#m2-hat-plus-installation). To boot from an NVMe drive attached to the M.2 HAT+, complete the [boot from NVMe instructions](https://www.raspberrypi.com/documentation/accessories/m2-hat-plus.html#boot-from-nvme).

Pay attention to the [instructions](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#pcie-gen-3-0) for switching from PCIe Gen 2 to PCIe Gen 3. Peripheral Component Interconnect Express (PCIe) is a high-speed interface that connects a computer's motherboard to other components. Non-volatile memory Express (NVMe), the communication interface used by Raspberry Pi SSDs, is compatible with PCIe Gen 3 and can significantly benefit from its increased data transfer speeds. You can expect data transfer speeds to be twice as fast as PCIe Gen 2. Below is the output of the commands I ran to check the speeds before and after this upgrade.


``` shell {linenos=false}
#Command executed when PCIe Gen 2 was enabled
$sudo hdparm -t --direct /dev/nvme0n1

/dev/nvme0n1:
 Timing O_DIRECT disk reads: 1252 MB in  3.00 seconds = 417.27 MB/sec

#Command executed when PCIe Gen 3 was enabled
$ sudo hdparm -t --direct /dev/nvme0n1
[sudo] password for pi:

/dev/nvme0n1:
 Timing O_DIRECT disk reads: 2376 MB in  3.00 seconds = 791.38 MB/sec
 ```
 
 #### Raspberry Pi 5 assembly with active cooler and SSD kit
 ![Raspberry Pi 5 assembly with active cooler and SSD kit](/images/content/pi5_assembly.jpg)
 
### Step 3: Install Container runtime on all the nodes

You can trace the history of Containerization to Virtualization, which started as early as the 1960s. IBM's CP-67 (CP/CMS) was the first commercial mainframe system that supported Virtualization. Virtualization is the process that forms the foundation for cloud computing; it relies on software known as a hypervisor that enables multiple virtual machines (VMs) to run on a single physical server. Each virtual machine has a guest operating system (OS), a virtual copy of the hardware that the OS requires to run, and its associated dependencies.

In contrast, modern-day containers are defined as units of software where application code is packaged with all its libraries and dependencies. Rather than virtualizing the underlying hardware like VMs, containers virtualize the operating system. The lack of the guest OS makes containers lightweight, faster, and more portable than VMs. 

By default, Kubernetes uses the [Container Runtime Interface (CRI)](https://v1-31.docs.kubernetes.io/docs/concepts/architecture/cri) to interface with your chosen container runtime. Kubernetes currently supports [Containerd](https://cri-o.io/), [CRI-O](https://cri-o.io/), [Podman](https://podman.io/) and [Mirantis](https://docs.mirantis.com/welcome/). Let's use Containerd, an industry-standard runtime known for being simple, robust, and portable. To set up Containerd, we execute the commands below.

```
###Load kernel modules
sudo modprobe overlay && \
sudo modprobe br_netfilter

#Setup apt-get sources
sudo mkdir -p /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

###Install containerd
sudo apt-get update -y && \
sudo apt-get install containerd.io

###Tweak config
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

###Enable containerd and check status
sudo systemctl enable containerd
sudo systemctl status containerd
```


### Step 4: Setup k8s on all the nodes

Despite many lightweight Kubernetes distributions, such as K3s, Microk8s, Kind, and Minikube, which make it very easy to get up and running with Kubernetes, we choose the difficult path of setting up the cluster with the official command line tool Kubeadm to align with our objective of diving deep into some of the Kubernetes internals. To get started, let's install kubeadm and its associated dependencies in all the nodes. The "kubeadm init" command should be executed only on the control plane node. When the initial command is successful, it will emit a cluster join command. Copy and save this, as you will need this in Step 6. If you get an error "/proc/sys/net/ipv4/ip_forward contents are not set to 1" during "kubeadm init", reboot the system and try again.

```
###Disable Swap Memory to avoid Kubelet failures
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

###Load kernel modules, for network overlay functionality
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

###Setup apt-get sources
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y && \
sudo apt-get install -y kubelet kubeadm kubectl kubernetes-cni && \
sudo apt-mark hold kubelet kubeadm kubectl kubernetes-cni

###Initialize kubeadm, run the below only on control plane node
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p  $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chmod 644 ~/.kube/config
kubectl get nodes -A -o wide
```

### Step 5: Install a Container Network Interface plugin

Kubernetes lets you use [Container Network Interface (CNI)](https://github.com/containernetworking/cni) plugins for cluster networking. You must use a CNI plugin that suits your cluster's needs. A CNI plugin is required to bring up the cluster. These implement the [Kubernetes network model](https://kubernetes.io/docs/concepts/services-networking/#the-kubernetes-network-model), which guarantees intra and inter-pod networking. Some of the popular CNI plugins are Flannel, Calico, and Weave. When choosing a CNI plugin, consider the layer in the OSI reference model where the plugin provider implemented overlay networking. The OSI model, Layer 2, the Data Link Layer, focuses on node-to-node data transfer using MAC addresses. At the same time, Layer 3, the Network Layer, handles routing packets across different networks based on IP addresses. Flannel, our CNI plugin of choice, configures a layer 3 IPv4 overlay network. In contrast, Weave, another CNI option, configures a Layer 2 overlay network using the Linux kernel features, managing routing between machines through a dedicated daemon. To learn more about CNI plugins and how they configure overlay networking in Kubernetes, see this [blog from Rancher Labs](https://www.suse.com/c/rancher_blog/comparing-kubernetes-cni-providers-flannel-calico-canal-and-weave/).

```
kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
```

### Step 6: Add nodes to the cluster.

Adding the nodes to the cluster is straightforward. You will need the join command you may have copied when initializing the kubeadm in the control plane node. If you missed copying the command, don't worry! You may regenerate it by running the below command line on a control plane node. Copy the result of this command and run it on all the worker nodes. if you get an error "/proc/sys/net/ipv4/ip_forward contents are not set to 1" during "sudo kubeadm join" reboot the system and try again. If you return to the control plane node and run "watch kubectl get nodes," you will see the worker nodes joining the cluster and eventually reaching a ready state. Let's install the free (for personal use) visual administration tool Lens to simplify cluster administration. To set it up for cluster administration, use the "Add Kubeconfigs" and point to a local copy of the "~/.kube/config" file from the control plane node.

```
#command to regenerate join command
kubeadm token create --print-join-command
```

Congratulations! If you have reached this far and completed the steps above, you should now have a cluster up and running. To make accessing the service endpoints and UIs seamless I would recommend installing an ingress controller like  [Ingress-Nginx](https://kubernetes.io/docs/concepts/services-networking/ingress/) or [Traefik](https://traefik.io/). In part 2 of this series, we focus on evolving this build by setting up storage services, the missing foundational building blocks of the cloud. These building blocks will help us test higher-level ML and analytics applications in a subsequent part of this series. 