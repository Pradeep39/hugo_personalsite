---
title: "Part 3 - Realize Object Storage and build your own website"
date: 2025-01-25
description: Build a personal private cloud with palm sized system on chips (SoCs)
menu:
  sidebar:
    name: Part 3 - Object Storage
    identifier: private-cloud-part3
    parent: private-cloud
    weight: 16
tags: ["Basic", "Multi-lingual"]
categories: ["Basic"]
---

In Part 1 of this series, we built a private cloud from the ground up using palm-sized raspberry pi 5's. Part 2 saw us implement distributed file and block storage resembling EFS and EBS in AWS. In this part, we will layer an S3 API-compliant object storage on top of the distributed file storage. By the end of this article, we will have all the foundational building blocks necessary to build web, mobile, data, analytics, and machine learning applications. We will test the stack by creating a personal portfolio website and hosting it on the World Wide Web. We will leverage the object storage to store and serve the static content, similar to how we can host a static website from S3, augmented by Amazon CloudFront's content distribution network capabilities. Although Implementing a content distribution network on top of Kubernetes is beyond the scope of our exploration, it's in the realm of possibility with solutions such as [KubeCDN](https://github.com/ilhaan/kubeCDN). To implement an S3-compliant object storage layer in Kubernetes, we chose MinIO. It is a widely tested and implemented alternative to AWS S3 for various applications. I chose Minio for its simplicity in provisioning and minimal operational overhead. Before we install Minio, let's meet the following prerequisites:

* Procure a domain for your portfolio website. You may use domain registrars like NameCheap or GoDaddy to purchase a domain. I bought "pradeepr.cloud" from https://www.namecheap.com for $5 a year.
* You can use an ingress controller such as Ingress-Nginx or Traefik to direct traffic for various applications and websites you plan to host on the private cloud. I chose Ingres-Nginx for its simplicity.
* MetalLB Load Balancer that can vend Virtual IP Addresses and load balances traffic across your applications/services nodes.

The solution architecture below, which we will realize at the end of this article, will provide an intuition for the roles of MetalLB, and Ingress-Nginx. For a quick preview, visit [pradeepr.cloud](http://pradeepr.cloud) and trace the path depicted below in the ethereal intercontinental expressway we know as the Internet. If you are curious about the A records and CNAME records on the top left corner of the infographic, you can set these up on your domain registrar's website. For a quick primer on the different DNS record types and their purpose, see this [CloudFlare article](https://www.cloudflare.com/learning/dns/dns-records/).

![Data Flow / Solution Architecture](/images/content/solution_arch.gif)

### Step 1: Install the Prerequisites

Install MetalLB and Ingress-Nginix by executing the simple helm install commands below.

```
helm install metallb metallb/metallb -n metallb-system --create-namespace

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace 
```

In Kubernetes, Services manifest in three different forms.
* "ClusterIP" services are only accessible within the cluster,
* "NodePort" services expose a service on a designated port on every node, allowing external access.
* "LoadBalancer" services utilize a cloud provider's load balancer or MetalLB to expose a service externally with advanced traffic distribution capabilities;

Nginx-Ingres is an ingress controller and reverse proxy responsible for routing web traffic to the appropriate service destination. To learn more about ingress click [here](https://kubernetes.io/docs/concepts/services-networking/ingress/#what-is-ingress) 

### Step 2: Configure MetalLB AddressPool and L2Advertisements
As illustrated in the animated infographic, MetalLB is a bare-metal network load balancer that assigns virtual IP addresses to load balancer services such as Nginx-Ingress and Minio. It does this by doing L2 and/or BGP advertisements.

* "L2 advertisements" refer to broadcasting service IP addresses on a local network using Layer 2 protocols like Address Resolution Protocol (ARP), making the service visible to nearby devices.
* "BGP advertisements" involve announcing service IP addresses across different networks using the Border Gateway Protocol (BGP), enabling wider reachability and load balancing.

We chose the L2 advertisement as we are dealing with a single home network. We register 
L2Advertisement by running the kubectl command below. I chose the 192.168.86.2-192.168.86.19 address range for the virtual IP address pool to keep the virtual IPs within the same subnet.

```
$ cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.86.2-192.168.86.19
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF
```

### Step 3: Install the MinioOperator using Helm Chart
Install MinioOperator by following the instructions on the [Deploy Operator with Helm documentation page](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-operator-helm.html). The [Kubernetes Operator framework](https://operatorframework.io/), not to be confused with Airflow Operator or the more recent ChatGPT Operator, allows providers to package, run, and maintain an application in an automated cloud-native way. Simply put, the goal of an Operator is to put operational knowledge into software. Previously, this knowledge was locked in administrators' minds or encoded in automation tools like Ansible.

The Kubernetes operator has two main components: a controller and a Custom Resource Definition (CRD), which defines the specification for a Custom Resource (CR). The controller is a program that runs in a loop and watches the CR for any changes, reconciling the actual state of the CR with the state defined in the CR manifest. The CRD and, consequently, the CR are extensions of the k8s API and do not exist in a k8s cluster by default. Following the installation instructions, we deploy the MinIO Operator using the below commands.

```
helm repo add minio-operator https://operator.min.io

helm install \
  --namespace minio-operator \
  --create-namespace \
  operator minio-operator/operator
```

### Step 4: Deploy the MinioTenant using the Helm Chart
We now deploy the MinioTenant, which creates storage isolation across users and applications. We accomplish this step by following the instructions at the [Deploy MinIO Tenant with Helm documentation page](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant-helm.html#id3). Regarding step 2 of the instructions, which instructs you to download and customize [Values.yaml](https://raw.githubusercontent.com/minio/operator/master/helm/tenant/values.yaml), MinIo recommends using the reclaim policy of "Retain" for the PVC [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes)  in values.yaml. Let's override the following config values to keep our configuration simple.

* Set "pools: servers" to the number of workers in your Raspberry Pi cluster, reduce the "pools: size" to conserve your storage bandwidth, and set "pools: storageClassName" to longhorn-efs.
* Set "exposeServices: minio" and "exposeServices: console" to true to allow the installation of load balancer services for the mini console and S3-compliant API. The MetalLB service automatically attaches a virtual IP address for all load balancer services.
* Set "certificate : requestAutoCert" to false and disable SSL/TLS. Enabling TLS with automatic certificate management is a complex subject in Kubernetes that warrants independent exploration.
* Override "configSecret: accessKey" and "configSecret: secretKey" to change the default user name and password.
* Finally, Override the Ingress Rules to allow the console and API services to be reachable on the Internet, in my case via "minio.console.pradeepr.cloud" and "minio.pradeepr.cloud".

For reference, see my [Values.yaml](https://raw.githubusercontent.com/Pradeep39/k8s_on_ubuntu/refs/heads/main/myminio-values.yaml) config overrides.

```
helm install \
--namespace myminio \
--create-namespace \
--values myminio-values.yaml \
myminio minio-operator/tenant
```

### Step 5 Create a public bucket and upload static content.
Let's create a bucket called "my site" using the Minio UI and make it public. We will use a popular static website content generator called [Hugo with the Taho theme](https://github.com/hugo-toha/toha) for a personal portfolio and a blog site. Following the instructions at Hugo-taho GitHub readme, you can generate a responsive personal portfolio site in 5-10 minutes. One nuance to remember is enabling [UglyURLs](https://gohugo.io/content-management/urls/#appearance) to generate HTML content in absolute URLs. The generated static content can now be uploaded using the web UI or S3 API. See below for a demonstration.

![Demo: Upload website content and serve from object storage](/images/content/upload_content.gif)

### Step 6 Create a domain redirection rule to direct traffic on your home page to the Minio bucket URL
Apply the below ingress config to redirect traffic from the home page [http://pradeepr.cloud](http://pradeepr.cloud) to the home.html object URL reachable via Minio API using the URL "http://minio.pradeepr.cloud/mysite/public/index.html".  Visit http://pradeepr.cloud to observe the redirection to the S3-compliant Minio bucket object, also captured in the animated infographic at the top of this article.

```
$ cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
data:
  allow-snippet-annotations: 'true'
  annotations-risk-level: Critical
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: domain-ingress
  namespace: myminio
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /home
    nginx.ingress.kubernetes.io/add-base-url : "true"
    nginx.ingress.kubernetes.io/server-snippet: |
     return 301 http://minio.pradeepr.cloud/mysite/public/index.html#;
spec:
  ingressClassName: nginx
  rules:
  - host: pradeepr.cloud
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: minio
            port:
              number: 80
EOF
```

Congratulations! If you have reached this far and completed the steps above, you should now have your personal portfolio website running on your private cloud. The private cloud is now complete with a distributed object storage foundational for building various cloud-based applications and solutions. In future parts of this series, we will move to higher ground and explore Data and AI applications on top of our private cloud. Keep watching this space!

***

### Addendum: Secure the site with TLS certificate using Cert Manager and LetsEncrypt 

HTTP is a protocol or set of communication rules for client-server communication over any network. HTTPS is the practice of establishing a secure SSL/TLS protocol on an insecure HTTP connection. Before it connects with a website, your browser uses TLS to check the website’s TLS or SSL certificate. TLS and SSL certificates show a server adheres to the current security standards. You can find evidence about the certificate within the browser address bar. An authentic and encrypted connection displays https:// instead of http://. The additional s stands for secure. At present, all SSL certificates are no longer in use.

![TLS Certificate in your browser](/images/content/tls_certificate.gif) 

TLS certificates are the industry standard. However, the industry continues to use the term SSL to refer to TLS certificates. For historical context, When the Internet Engineering Task Force (IETF) updated SSL version 3.0, instead of being called SSLv4.0, it was renamed TLSv1.0. To understand how TLS works, see this CloudFlare article. Browse this tutorial for instructions on how to install and secure ingress to your cluster using NGINX-ingress controller.

***

