# 1. 只更新 master 证书  

小于等于`v1.9`版本，etcd默认是不使用TLS连接，没有etcd相关证书，只需要更新master证书即可

master 和 etcd 分开节点部署的情况，需要分别更新 etcd 和 master 证书



如果有多个master节点，在每个master节点都执行一次  

```
./update-kubeadm-cert.sh master
```

将更新以下master证书和kubeconfig配置文件  

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



# 2. 只更新etcd证书 

master 和 etcd 分开节点部署的情况，需要分别更新 etcd 和 master 证书



如果有多个etcd节点，在每个etcd节点上都执行一次  

```
./update-kubeadm-cert.sh etcd
```

将更新以下etcd证书  

```
/etc/kubernetes
 └── pki
  ├── apiserver-etcd-client.crt
  └── etcd
      ├── healthcheck-client.crt
      ├── peer.crt
      └── server.crt
```



# 3. 使用脚本处理后证书是延续10年吗？

并不是  

kubeadm 签发的 CA 默认有效期是 10 年 (从 init 集群那一刻开始算)，当 CA 到期后，整套证书体系都时效了  

换句话说，10 年有效期是从 init 集群那一刻开始算的，不是从执行脚本更新证书那一刻开始算的  



# 4. kubeadm 证书相关命令发展

- `v1.8` 版开始提供了证书生成命令 `kubeadm alpha phase certs <cert_name>`
- `v1.13` 版开始证书生成命令改为 `kubeadm init phase certs <cert_name>`
- `v1.15` 版增加了证书更新命令 `kubeadm alpha certs renew <cert_name>`（这个命令与上面两个区别是：上面两个是生成证书，这个是更新证书），`v1.15` 版之后建议使用 `kubeadm alpha certs renew <cert_name>` 来更新证书



# 5. kubeadm 命令更新证书手动处理

使用本脚本脚本更新证书，不涉及以下这个bug，无需手动处理

bug 见 https://github.com/kubernetes/kubeadm/issues/1753 ，这个bug 在 `1.17` 版修复

针对小于  `1.17版本` ，使用  `kubeadm alpha certs renew <cert_name>`  来更新证

`kubeadm alpha certs renew`  并不会更新 kubelet 证书（kubelet.conf 文件里面写的客户端证书），因为 kubelet 证书是默认开启自动轮回更新的，但是在执行 `kubeadm init` 的 master 节点的 kubelet.conf 文件里面的证书是以 base64 编码写死的 (和 controller-manager.conf 一样)

在用 `kubeadm`  命令更新 master 证书时需要手动将 kubelet.conf 文件的  `client-certificate-data`  和  `client-key-data`  改为：

```yaml
client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem
client-key: /var/lib/kubelet/pki/kubelet-client-current.pem
```



