**该脚本用于处理已过期或者即将过期的kubernetes集群证书**  

kubeadm生成的证书有效期为为1年，该脚本可将kubeadm生成的证书有效期更新为10年  

该脚本只处理master节点上的证书：kubeadm默认配置了kubelet证书自动更新，node节点kubelet.conf所指向的证书会自动更新  

*小于`v1.17`版本的master初始化节点(执行kubeadm init的节点) kubelet.conf里的证书并不会自动更新，这算是一个[bug](<https://github.com/kubernetes/kubeadm/issues/1753>)，该脚本会一并处理更新master节点的kubelet.conf所包含的证书*   

# 1. 使用说明

小于等于`v1.9`版本，etcd默认是不使用TLS连接，没有etcd相关证书，只需要更新master证书即可

大于等于`v1.10`版本，etcd默认开启TLS，需要更新etcd证书和master证书  

**该脚本适用于所有k8s版本集群证书更新，但大于等于v1.15版本建议使用kubeadm命令更新**  

**该脚本仅需要在master和etcd节点执行，无需在node节点执行**  

## 1.1. 拉取脚本

```
git clone https://github.com/yuyicai/update-kube-cert.git
cd update-kubeadm-cert
chmod 755 update-kubeadm-cert.sh
```
*执行时请使用`./update-kubeadm-cert.sh all`或者`bash update-kubeadm-cert.sh all`，不要使用`sh update-kubeadm-cert.sh`，因为某些发行版sh并不是链接到bash，会不兼容*  

## 1.2. 同时更新etcd证书和master证书  
如果master和etcd在同一个节点，执行以下命令更新证书全部etcd证书和master证书  

如果有多个master节点，在每个master节点都执行一次  

```
./update-kubeadm-cert.sh all
```
将更新以下证书和kubeconfig配置文件  
```
/etc/kubernetes
├── admin.conf
├── controller-manager.conf
├── scheduler.conf
├── kubelet.conf
└── pki
    ├── apiserver.crt
    ├── apiserver-etcd-client.crt
    ├── apiserver-kubelet-client.crt
    ├── front-proxy-client.crt
    └── etcd
        ├── healthcheck-client.crt
        ├── peer.crt
        └── server.crt
```

## 1.3. 只更新etcd证书 
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

## 1.4. 只更新master证书  
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



# 2. 证书更新失败回滚

脚本会自动备份`/etc/kubernetes`目录到`/etc/kubernetes.old-$(date +%Y%m%d)`目录（备份目录名录示例：kubernetes.old-20200325）

若更新证书失败需要回滚，手动将份`/etc/kubernetes.old-$(date +%Y%m%d)`目录覆盖`/etc/kubernetes`目录  



# 3. kubeadm 证书相关命令发展

- `v1.8`版开始提供了证书生成命令`kubeadm alpha phase certs <cert_name>`
- `v1.13`版开始证书生成命令改为`kubeadm init phase certs <cert_name>`
- `v1.15`版增加了证书更新命令`kubeadm alpha certs renew <cert_name>`（这个命令与上面两个区别是：上面两个是生产证书，这个是更新证书），`v1.15`版之后建议使用`kubeadm alpha certs renew <cert_name>`来更新证书



# 4. 关于大于等于v1.15版本

大于等于`v1.15`的版本建议直接使用`kubeadm alpha certs renew <cert_name>`来更新证书有效期，更新后延长一年  

小坑：  

`kubeadm alpha certs renew` 并不会更新kubelet证书（kubelet.conf文件里面写的客户端证书），因为kubelet证书是默认开启自动更新的  

但是在执行`kubeadm init`的master节点的kubelet.conf文件里面的证书是以base64编码写死在conf文件的（和controller-manager.conf）一样，在用kubeadm命令更新master证书时需要手动将kubelet.conf文件的 `client-certificate-data` 和 `client-key-data` 该为：

```yaml
client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem
client-key: /var/lib/kubelet/pki/kubelet-client-current.pem
```

（这个问题在`v1.17`版得到了解决https://github.com/kubernetes/kubeadm/issues/1753）

