
更新kubeadm生成的证书有效期为10年  

kubeadm生成的证书有效期为为1年，虽然`1.8`版开始提供了证书生成命令（kubeadm alpha phase certs <cert_name>，`1.13`版开始改为kubeadm init phase certs <cert_name>）

但是`1.11`版之前执行kubeadm alpha phase certs <cert_name>命令，连不上dl.k8s.io会报错以下错误，从而无法单纯只更新证书    
```
unable to get URL "https://dl.k8s.io/release/stable-1.11.txt": Get https://dl.k8s.io/release/stable-1.11.txt: dial tcp 35.201.71.162:443: i/o timeout
```

（`1.12`版之后连不上dl.k8s.io也会执行，`1.12`之后版可以使用`kubeadm`来更新证书，`1.15`版之后增加了证书更新命令`kubeadm alpha certs renew <cert_name>`，更新证书更加方便了）  

但是你还是**旧版 kubeadm**本，那么可以用这个脚本来更新你的证书，生成证书默认有效期为10年（3650天），你可以更改脚本里面的`CAER_DAYS`变量来达到你想要的证书有效期，单位是“天”  

（kubeadm默认生成是ca有效期是10年，你把`CAER_DAYS`改成太大也没用，因为你master相关证书过期的时候已经过去一年了，ca只剩下9年的有效期了）

（node节点kubelet证书快过期的时候会自动更新，通常不会和master相关证书一起过期）  

脚本只更新证书，key使用原来的key  

# 使用说明
## 更新etcd证书和master证书  
如果master和etcd在同一个节点，执行以下命令更新证书全部etcd证书和master证书，如果你有多个master节点（和etcd节点重合），那么在每个master节点都执行一次  
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

## 只更新etcd证书 
如果你有多个etcd节点，在每个节点上都执行一次  
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

## 只更新master证书  
如果你有多个master节点，那么在每个节点都执行一次  
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

# 示例
## 更新已过期证书
- 小于等于1.9版本，etcd默认是不使用TLS连接的，所以默认没有etcd相关证书，只需要更新master证书即可  
  （具体etcd是否开启TLS，查看是否存在etcd证书，或者从静态pod文件配置判断）  
  ```
  ./update-kubeadm-cert.sh master
  ```
- 大于等于1.10版本，etcd默认开启TLS，需要更新etcd证书和master证书   
  ```
  ./update-kubeadm-cert.sh etcd
  ./update-kubeadm-cert.sh master
  ```
## 证书未过期，更新证书
如果你使用kubeadm生成的证书未过期，例如你更刚安装完毕集群的时候，也可以用此脚本来更新你的证书有效期为10年。  
```
./update-kubeadm-cert.sh all
```
