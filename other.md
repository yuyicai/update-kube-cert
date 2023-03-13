# 1. Update master node's certificate only

If the version of your cluster is less than or equal to `v1.9`, etcd does not use TLS connection by default. You need to update master node's certificate only.

If there are multiple master nodes, execute on each node:

```
./update-kubeadm-cert.sh master
```

The following master certificate and kubeconfig configuration files will be updated:

```
/etc/kubernetes
├── admin.conf
├── controller-manager.conf
├── scheduler.conf
├── kubelet.conf
└── pki
    ├── apiserver.crt
    ├── apiserver-kubelet-client.crt
    └── front-proxy-client.crt
```

# 2. Is the certificate valid for 10 years after executing the script?

No, technically.

The default CA that issued by kubeadm is valid for 10 years (from the moment you init the cluster). And the whole certificate system will expire when the CA expires.

In other words, the 10-year validity period starts from the moment the cluster is initiated, instead of from the moment the script is executed to renew the certificate.

# 3. The history of kubeadm certificate related commands

- Since `v1.8`, it provides the certificate generation command `kubeadm alpha phase certs <cert_name>`.
- The command changed to `kubeadm init phase certs <cert_name>` in `v1.13`
- The certificate renewal command `kubeadm alpha certs renew <cert_name>` comes since `v1.15`. (the difference between this command and the above two is: The above two are to generate certificates. But this one is to renew certificates) So after `v1.15`, you can simply use `kubeadm alpha certs renew <cert_name>` to renew certificates. name>` to renew the certificate

# 4. handle kubeadm command bug manually

If use this script to update the certificate, this bug won't appear. And there is no need to handle it.

See https://github.com/kubernetes/kubeadm/issues/1753 for the detail of the bug, which was fixed in `1.17` version.

For versions less than `1.17`, use `kubeadm alpha certs renew <cert_name>` to renew the certificate.

`kubeadm alpha certs renew` does not renew the kubelet certificate (the client certificate written in the kubelet.conf file) because the kubelet certificate is automatically renewed by default. But in the kubelet.conf file of the master node where `kubeadm init` is executed, the certificate is hard coded in base64 encoding format. (like the controller-manager.conf certificate)

When updating the master certificate with the `kubeadm` command, you need to manually change the `client-certificate-data` and `client-key-data` in the kubelet.conf file to the following contents:

```yaml
client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem
client-key: /var/lib/kubelet/pki/kubelet-client-current.pem
```
