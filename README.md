# update-kube-cert

更新kubeadm生成的证书有效期为10年  

kubeadm生成的证书有效期为为1年，虽然1.8半开始提供了证书生成命令（kubeadm alpha phase certs <cert_name>，1.13版开始改为kubeadm init phase certs <cert_name>）
但是1.11版之前执行kubeadm alpha phase certs <cert_name>命令，连不上dl.k8s.io会报错  
```
unable to get URL "https://dl.k8s.io/release/stable-1.11.txt": Get https://dl.k8s.io/release/stable-1.11.txt: dial tcp 35.201.71.162:443: i/o timeout
```
从而无法单纯只更新证书  
（1.12版之后连不上dl.k8s.io也会执行，1.12之后版可以使用kubeadm来更新证书，1.15版之后增加了证书更新命令，更新证书更加方便了） 
但是你还是旧版本，那么可以用这个脚本来更新你的证书，证书有限期默认这种为10年，你可以更改脚本里面的CAER_DAYS变量来达到你想要的证书有效期，单位是“天”  

- 更新etcd证书和master证书   
  ```
  ./update-k8s-cert.sh
  ```

- 只更新etcd证书  
  ```
  ./update-k8s-cert.sh etcd
  ```

- 只更新master证书  
  ```
  ./update-k8s-cert.sh etcd
  ```


# 更新已过期证书
在master节点执行  
```
./update-k8s-cert.sh
```

# 证书未过期，更新证书
如果你使用kubeadm生成的证书未过期，比如你更刚安装完毕集群的时候，也可以用此脚本来更新你的证书有效期为10年。  
```
./update-k8s-cert.sh
```