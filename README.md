# update-kube-cert

A tool to update and extend Kubernetes certificate expiration dates in kubeadm-initiated clusters.

## Overview

This script helps you manage Kubernetes certificates by:  

- Extending certificate validity to 10 years for existing Kubernetes clusters. (includes both cluster with certificate expiration issues and normal cluster)  
- Generating long-lived CA certificates (100 years) before initializing new clusters

## Usage

### Get the Script

```bash
git clone https://github.com/yuyicai/update-kube-cert.git
cd update-kube-cert
```

### For Existing Clusters

Renew certificates to 10 years:  
Run on all control plane nodes (master0, master1, master2...)

```bash
bash update-kubeadm-cert.sh --cri containerd
```

<details>

<summary>Terminal Output</summary>

```bash
root@master0:~/update-kube-cert# bash update-kubeadm-cert.sh --cri containerd
[2025-04-01T00:09:48.47+0800] [INFO] checking if all certificate files are existed...
[2025-04-01T00:09:48.47+0800] [INFO] backup /etc/kubernetes to /etc/kubernetes.old-2025-04-01_00-09-48
[2025-04-01T00:09:48.48+0800] [INFO] checking certificate expiration before update...
|-----------------------------------|----------------------------|
| CERTIFICATE                       | EXPIRES                    |
| ca.crt                            | Mar 29 16:09:05 2035 GMT   |
| apiserver.crt                     | Mar 31 16:09:05 2026 GMT   |
| apiserver-kubelet-client.crt      | Mar 31 16:09:05 2026 GMT   |
| front-proxy-ca.crt                | Mar 29 16:09:05 2035 GMT   |
| front-proxy-client.crt            | Mar 31 16:09:05 2026 GMT   |
|-----------------------------------|----------------------------|
| controller-manager.conf           | Mar 31 16:09:05 2026 GMT   |
| scheduler.conf                    | Mar 31 16:09:05 2026 GMT   |
| admin.conf                        | Mar 31 16:09:05 2026 GMT   |
| super-admin.conf                  | Mar 31 16:09:05 2026 GMT   |
|-----------------------------------|----------------------------|
| etcd/ca.crt                       | Mar 29 16:09:05 2035 GMT   |
| etcd/server.crt                   | Mar 31 16:09:05 2026 GMT   |
| etcd/peer.crt                     | Mar 31 16:09:05 2026 GMT   |
| etcd/healthcheck-client.crt       | Mar 31 16:09:05 2026 GMT   |
| apiserver-etcd-client.crt         | Mar 31 16:09:05 2026 GMT   |
|-----------------------------------|----------------------------|
[2025-04-01T00:09:48.52+0800] [INFO] updating certificates with 3650 days expiration...
[2025-04-01T00:09:48.53+0800] [INFO] updated /etc/kubernetes/pki/etcd/server.crt
[2025-04-01T00:09:48.55+0800] [INFO] updated /etc/kubernetes/pki/etcd/peer.crt
[2025-04-01T00:09:48.56+0800] [INFO] updated /etc/kubernetes/pki/etcd/healthcheck-client.crt
[2025-04-01T00:09:48.57+0800] [INFO] updated /etc/kubernetes/pki/apiserver-etcd-client.crt
[2025-04-01T00:09:48.59+0800] [INFO] restarted etcd
[2025-04-01T00:09:48.61+0800] [INFO] updated /etc/kubernetes/pki/apiserver.crt
[2025-04-01T00:09:48.62+0800] [INFO] updated /etc/kubernetes/pki/apiserver-kubelet-client.crt
[2025-04-01T00:09:48.63+0800] [INFO] updated /etc/kubernetes/controller-manager.conf
[2025-04-01T00:09:48.65+0800] [INFO] updated /etc/kubernetes/scheduler.conf
[2025-04-01T00:09:48.66+0800] [INFO] updated /etc/kubernetes/admin.conf
[2025-04-01T00:09:48.68+0800] [INFO] updated /etc/kubernetes/super-admin.conf
[2025-04-01T00:09:48.69+0800] [INFO] updated /etc/kubernetes/pki/front-proxy-client.crt
[2025-04-01T00:09:48.71+0800] [INFO] restarted control-plane pod: apiserver
[2025-04-01T00:09:48.73+0800] [INFO] restarted control-plane pod: controller-manager
[2025-04-01T00:09:48.76+0800] [INFO] restarted control-plane pod: scheduler
[2025-04-01T00:09:48.83+0800] [INFO] restarted kubelet
[2025-04-01T00:09:48.83+0800] [INFO] checking certificate expiration after update...
|-----------------------------------|----------------------------|
| CERTIFICATE                       | EXPIRES                    |
| ca.crt                            | Mar 29 16:09:05 2035 GMT   |
| apiserver.crt                     | Mar 29 16:09:48 2035 GMT   |
| apiserver-kubelet-client.crt      | Mar 29 16:09:48 2035 GMT   |
| front-proxy-ca.crt                | Mar 29 16:09:05 2035 GMT   |
| front-proxy-client.crt            | Mar 29 16:09:48 2035 GMT   |
|-----------------------------------|----------------------------|
| controller-manager.conf           | Mar 29 16:09:48 2035 GMT   |
| scheduler.conf                    | Mar 29 16:09:48 2035 GMT   |
| admin.conf                        | Mar 29 16:09:48 2035 GMT   |
| super-admin.conf                  | Mar 29 16:09:48 2035 GMT   |
|-----------------------------------|----------------------------|
| etcd/ca.crt                       | Mar 29 16:09:05 2035 GMT   |
| etcd/server.crt                   | Mar 29 16:09:48 2035 GMT   |
| etcd/peer.crt                     | Mar 29 16:09:48 2035 GMT   |
| etcd/healthcheck-client.crt       | Mar 29 16:09:48 2035 GMT   |
| apiserver-etcd-client.crt         | Mar 29 16:09:48 2035 GMT   |
|-----------------------------------|----------------------------|
[2025-04-01T00:09:48.89+0800] [INFO] DONE!!!enjoy it

please copy admin.conf to /root/.kube/config manually.
    # back old config
    cp /root/.kube/config /root/.kube/config_backup
    # copy new admin.conf to /root/.kube/config for kubectl manually
    cp -i /opt/kube/tmp/kubernetes/admin.conf /root/.kube/config


root@master0:~/update-kube-cert# kubectl get po -A
NAMESPACE     NAME                              READY   STATUS    RESTARTS        AGE
kube-system   coredns-668d6bf9bc-7kwkk          0/1     Pending   0               37m
kube-system   coredns-668d6bf9bc-b68dx          0/1     Pending   0               37m
kube-system   etcd-master0                      1/1     Running   4 (4m21s ago)   37m
kube-system   kube-apiserver-master0            1/1     Running   2 (60s ago)     37m
kube-system   kube-controller-manager-master0   1/1     Running   4 (49s ago)     37m
kube-system   kube-proxy-5mf68                  1/1     Running   0               37m
kube-system   kube-scheduler-master0            1/1     Running   3 (48s ago)     37m
root@master0:~/update-kube-cert#
root@master0:~/update-kube-cert# crictl --runtime-endpoint unix:///run/containerd/containerd.sock pods
POD ID              CREATED              STATE               NAME                              NAMESPACE           ATTEMPT             RUNTIME
59935ee07550b       About a minute ago   Ready               kube-apiserver-master0            kube-system         2                   (default)
37b73945aee1f       About a minute ago   NotReady            kube-apiserver-master0            kube-system         1                   (default)
5f05c3a5abfac       4 minutes ago        Ready               etcd-master0                      kube-system         4                   (default)
40c2c1480cbc8       5 minutes ago        Ready               kube-controller-manager-master0   kube-system         1                   (default)
781806f0cc91d       6 minutes ago        NotReady            etcd-master0                      kube-system         3                   (default)
75b68162b9476       37 minutes ago       Ready               kube-proxy-5mf68                  kube-system         0                   (default)
dc3da94fda7f9       37 minutes ago       Ready               kube-scheduler-master0            kube-system         0                   (default)
```

</details>

### For New Clusters

Generate 100 year CA certificates before running `kubeadm init`  
Just generate CA on the first control plane node (master0, which will run `kubeadm init`)   

```bash
# master0
# 1. Generate 100 years CA certificates
bash update-kubeadm-cert.sh --action gen-ca

# 2. Initialize your cluster with kubeadm
# kubeadm will use the existing CA certificates generated by the script
kubeadm init [options]

# 3. Update all certificates to 100 years use extended expiration
bash update-kubeadm-cert.sh --cri containerd --days 36500

# 4. Join master1, master2 to the cluster and just run 'bash update-kubeadm-cert.sh --cri containerd --days 36500' on them
```

<details>

<summary>Key Kubeadm init Output</summary>
kubeadm uses the existing CA certificates generated by the script

```bash
...
[certs] Using existing ca certificate authority
...
[certs] Using existing front-proxy-ca certificate authority
...
[certs] Using existing etcd/ca certificate authority
...
```

</details>


<details>

<summary>Full terminal Output</summary>

```bash
root@master0:~/update-kube-cert# bash update-kubeadm-cert.sh --action gen-ca
[2025-04-01T00:14:35.89+0800] [INFO] generating CA with 36500 days expiration...
[2025-04-01T00:14:35.90+0800] [INFO] generating k8s CA...
[2025-04-01T00:14:36.06+0800] [INFO] generated /etc/kubernetes/pki/ca.crt
[2025-04-01T00:14:36.06+0800] [INFO] generating front-proxy CA...
[2025-04-01T00:14:36.11+0800] [INFO] generated /etc/kubernetes/pki/front-proxy-ca.crt
[2025-04-01T00:14:36.11+0800] [INFO] generating etcd CA...
[2025-04-01T00:14:36.14+0800] [INFO] generated /etc/kubernetes/pki/etcd/ca.crt
|-----------------------------------|----------------------------|
| CERTIFICATE                       | EXPIRES                    |
| ca.crt                            | Mar  7 16:14:36 2125 GMT   |
| apiserver.crt                     |                            |
| apiserver-kubelet-client.crt      |                            |
| front-proxy-ca.crt                | Mar  7 16:14:36 2125 GMT   |
| front-proxy-client.crt            |                            |
|-----------------------------------|----------------------------|
| controller-manager.conf           |                            |
| scheduler.conf                    |                            |
| admin.conf                        |                            |
|-----------------------------------|----------------------------|
| etcd/ca.crt                       | Mar  7 16:14:36 2125 GMT   |
| etcd/server.crt                   |                            |
| etcd/peer.crt                     |                            |
| etcd/healthcheck-client.crt       |                            |
| apiserver-etcd-client.crt         |                            |
|-----------------------------------|----------------------------|
[2025-04-01T00:14:36.18+0800] [INFO] DONE!!! generated CA for new cluster.
    # create new cluster after generating CA, you can use the following command:
      kubeadm init [options]
    # after running kubeadm init, update certificates for 100 yeas
      bash update-kubeadm-cert.sh --cri containerd --days 36500
root@master0:~/update-kube-cert#
root@master0:~/update-kube-cert#
root@master0:~/update-kube-cert# kubeadm init
[init] Using Kubernetes version: v1.32.3
[preflight] Running pre-flight checks
	[WARNING SystemVerification]: cgroups v1 support is in maintenance mode, please migrate to cgroups v2
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
W0401 00:15:10.683957   13914 checks.go:846] detected that the sandbox image "" of the container runtime is inconsistent with that used by kubeadm.It is recommended to use "registry.k8s.io/pause:3.10" as the CRI sandbox image.
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Using existing ca certificate authority
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local master0] and IPs [10.96.0.1 10.0.0.186]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Using existing front-proxy-ca certificate authority
[certs] Generating "front-proxy-client" certificate and key
[certs] Using existing etcd/ca certificate authority
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost master0] and IPs [10.0.0.186 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost master0] and IPs [10.0.0.186 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "super-admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests"
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 501.312263ms
[api-check] Waiting for a healthy API server. This can take up to 4m0s
[api-check] The API server is healthy after 3.501053598s
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node master0 as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node master0 as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: pwjq3f.6vdgdbfy8mk3gq0s
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.0.0.186:6443 --token pwjq3f.6vdgdbfy8mk3gq0s \
	--discovery-token-ca-cert-hash sha256:6cef6024c7b0a25a2b81c31907248a2dc124eada0fd7abd565bbe60d6ad775a1
root@master0:~/update-kube-cert#
root@master0:~/update-kube-cert#
root@master0:~/update-kube-cert# bash update-kubeadm-cert.sh --cri containerd --days 36500
[2025-04-01T00:16:12.09+0800] [INFO] checking if all certificate files are existed...
[2025-04-01T00:16:12.09+0800] [INFO] backup /etc/kubernetes to /etc/kubernetes.old-2025-04-01_00-16-12
[2025-04-01T00:16:12.09+0800] [INFO] checking certificate expiration before update...
|-----------------------------------|----------------------------|
| CERTIFICATE                       | EXPIRES                    |
| ca.crt                            | Mar  7 16:14:36 2125 GMT   |
| apiserver.crt                     | Mar 31 16:15:10 2026 GMT   |
| apiserver-kubelet-client.crt      | Mar 31 16:15:10 2026 GMT   |
| front-proxy-ca.crt                | Mar  7 16:14:36 2125 GMT   |
| front-proxy-client.crt            | Mar 31 16:15:10 2026 GMT   |
|-----------------------------------|----------------------------|
| controller-manager.conf           | Mar 31 16:15:10 2026 GMT   |
| scheduler.conf                    | Mar 31 16:15:10 2026 GMT   |
| admin.conf                        | Mar 31 16:15:10 2026 GMT   |
| super-admin.conf                  | Mar 31 16:15:10 2026 GMT   |
|-----------------------------------|----------------------------|
| etcd/ca.crt                       | Mar  7 16:14:36 2125 GMT   |
| etcd/server.crt                   | Mar 31 16:15:10 2026 GMT   |
| etcd/peer.crt                     | Mar 31 16:15:10 2026 GMT   |
| etcd/healthcheck-client.crt       | Mar 31 16:15:10 2026 GMT   |
| apiserver-etcd-client.crt         | Mar 31 16:15:10 2026 GMT   |
|-----------------------------------|----------------------------|
[2025-04-01T00:16:12.14+0800] [INFO] updating certificates with 36500 days expiration...
[2025-04-01T00:16:12.15+0800] [INFO] updated /etc/kubernetes/pki/etcd/server.crt
[2025-04-01T00:16:12.16+0800] [INFO] updated /etc/kubernetes/pki/etcd/peer.crt
[2025-04-01T00:16:12.17+0800] [INFO] updated /etc/kubernetes/pki/etcd/healthcheck-client.crt
[2025-04-01T00:16:12.18+0800] [INFO] updated /etc/kubernetes/pki/apiserver-etcd-client.crt
[2025-04-01T00:16:12.21+0800] [INFO] restarted etcd
[2025-04-01T00:16:12.22+0800] [INFO] updated /etc/kubernetes/pki/apiserver.crt
[2025-04-01T00:16:12.23+0800] [INFO] updated /etc/kubernetes/pki/apiserver-kubelet-client.crt
[2025-04-01T00:16:12.25+0800] [INFO] updated /etc/kubernetes/controller-manager.conf
[2025-04-01T00:16:12.26+0800] [INFO] updated /etc/kubernetes/scheduler.conf
[2025-04-01T00:16:12.28+0800] [INFO] updated /etc/kubernetes/admin.conf
[2025-04-01T00:16:12.29+0800] [INFO] updated /etc/kubernetes/super-admin.conf
[2025-04-01T00:16:12.30+0800] [INFO] updated /etc/kubernetes/pki/front-proxy-client.crt
[2025-04-01T00:16:12.33+0800] [INFO] restarted control-plane pod: apiserver
[2025-04-01T00:16:12.35+0800] [INFO] restarted control-plane pod: controller-manager
[2025-04-01T00:16:12.37+0800] [INFO] restarted control-plane pod: scheduler
[2025-04-01T00:16:12.42+0800] [INFO] restarted kubelet
[2025-04-01T00:16:12.42+0800] [INFO] checking certificate expiration after update...
|-----------------------------------|----------------------------|
| CERTIFICATE                       | EXPIRES                    |
| ca.crt                            | Mar  7 16:14:36 2125 GMT   |
| apiserver.crt                     | Mar  7 16:16:12 2125 GMT   |
| apiserver-kubelet-client.crt      | Mar  7 16:16:12 2125 GMT   |
| front-proxy-ca.crt                | Mar  7 16:14:36 2125 GMT   |
| front-proxy-client.crt            | Mar  7 16:16:12 2125 GMT   |
|-----------------------------------|----------------------------|
| controller-manager.conf           | Mar  7 16:16:12 2125 GMT   |
| scheduler.conf                    | Mar  7 16:16:12 2125 GMT   |
| admin.conf                        | Mar  7 16:16:12 2125 GMT   |
| super-admin.conf                  | Mar  7 16:16:12 2125 GMT   |
|-----------------------------------|----------------------------|
| etcd/ca.crt                       | Mar  7 16:14:36 2125 GMT   |
| etcd/server.crt                   | Mar  7 16:16:12 2125 GMT   |
| etcd/peer.crt                     | Mar  7 16:16:12 2125 GMT   |
| etcd/healthcheck-client.crt       | Mar  7 16:16:12 2125 GMT   |
| apiserver-etcd-client.crt         | Mar  7 16:16:12 2125 GMT   |
|-----------------------------------|----------------------------|
[2025-04-01T00:16:12.48+0800] [INFO] DONE!!!enjoy it

please copy admin.conf to /root/.kube/config manually.
    # back old config
    cp /root/.kube/config /root/.kube/config_backup
    # copy new admin.conf to /root/.kube/config for kubectl manually
    cp -i /opt/kube/tmp/kubernetes/admin.conf /root/.kube/config
root@master0:/etc/kubernetes#
root@master0:/etc/kubernetes# cp /opt/kube/tmp/kubernetes/admin.conf /root/.kube/config
root@master0:/etc/kubernetes#
root@master0:/etc/kubernetes# kubeadm certs check-expiration
[check-expiration] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[check-expiration] Use 'kubeadm init phase upload-config --config your-config.yaml' to re-upload it.

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Mar 07, 2125 16:16 UTC   99y             ca                      no
apiserver                  Mar 07, 2125 16:16 UTC   99y             ca                      no
apiserver-etcd-client      Mar 07, 2125 16:16 UTC   99y             etcd-ca                 no
apiserver-kubelet-client   Mar 07, 2125 16:16 UTC   99y             ca                      no
controller-manager.conf    Mar 07, 2125 16:16 UTC   99y             ca                      no
etcd-healthcheck-client    Mar 07, 2125 16:16 UTC   99y             etcd-ca                 no
etcd-peer                  Mar 07, 2125 16:16 UTC   99y             etcd-ca                 no
etcd-server                Mar 07, 2125 16:16 UTC   99y             etcd-ca                 no
front-proxy-client         Mar 07, 2125 16:16 UTC   99y             front-proxy-ca          no
scheduler.conf             Mar 07, 2125 16:16 UTC   99y             ca                      no
super-admin.conf           Mar 07, 2125 16:16 UTC   99y             ca                      no

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Mar 07, 2125 16:14 UTC   99y             no
etcd-ca                 Mar 07, 2125 16:14 UTC   99y             no
front-proxy-ca          Mar 07, 2125 16:14 UTC   99y             no
```

</details>

## After Running
Copy the admin configuration to your kubectl config directory

```bash
# Backup existing config
cp $HOME/.kube/config $HOME/.kube/config_backup

# Copy new config
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
```

## Options
``` bash
    -c, --cri     <docker|containerd> (default: containerd)
                    Set the cri type, in order to restart control-plane and etcd service by different command, 'docker' or 'crictl'.
    -a, --action  <update|check|gen-ca> (default: update)
                    update: Update certificates 10 years for existing clusters
                    check: Only check the expiration of the certificates without updating them.
                    gen-ca: Generate 100 years CA before kubeadm init cluster. (only used for new clusters, not for existing clusters)
    --days        Set the number of days for certificate expiration. (default: 3650)
    -h, --help    Show this help message and exit.
```

## Certificate Files Updated
certificates files:
```
/etc/kubernetes/pki/apiserver.crt
/etc/kubernetes/pki/apiserver-kubelet-client.crt
/etc/kubernetes/pki/front-proxy-client.crt
/etc/kubernetes/pki/apiserver-etcd-client.crt
/etc/kubernetes/pki/etcd/server.crt
/etc/kubernetes/pki/etcd/peer.crt
/etc/kubernetes/pki/etcd/healthcheck-client.crt
```
kubeconfig files:
```
/etc/kubernetes/admin.conf
/etc/kubernetes/controller-manager.conf
/etc/kubernetes/scheduler.conf
/etc/kubernetes/super-admin.conf (after Kubernetes v1.29.0, this script will check automatically)
/etc/kubernetes/kubelet.conf (before Kubernetes v1.17.0, this script will check automatically)
```

## FAQ

- **Can I generate CA for 100 years on an existing cluster by this script?**  
  No, this script only updates the certificates on existing clusters, not including CA.  

- **How can I Change CA for an existing cluster?**  
  See: https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/

- **If I have a multi-master cluster, do I need to run this on all master?**  
  Yes, you should run this script on all control plane nodes, by not on worker nodes.

- **How to force restart control-plane pods manually?**  
  If any control plane components couldn't be automatically restarted, you should manually restart them.

  ```bash
  # Make sure kubelet is running
  systemctl restart kubelet

  # Move manifests to trigger kubelet to recreate the pods
  mv /etc/kubernetes/manifests /etc/kubernetes/manifests_backup

  # Wait for kubelet to remove the old pods
  sleep 120

  # Restore manifests, kubelet will recreate the pods
  mv /etc/kubernetes/manifests_backup /etc/kubernetes/manifests

  # Check the status of control-plane pods
  kubectl get pods -n kube-system -o wide
  ```

- **What happens if the script fails?**  
  The script performs backup of critical files before making changes. If it fails, you can find backups in `/etc/kubernetes.old-$(date +%Y-%m-%d_%H-%M-%S)`.

- **Can I run this on worker nodes?**  
  No, this script should only be run on control plane nodes.

- **Will this cause downtime?**  
  There might be a brief disruption while control plane components restart with new certificates.  
  But on multi-master clusters, the disruption should be minimal.

## License
MIT License
