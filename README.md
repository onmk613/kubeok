# kubeok

## Ansible Server 节点

### 二进制文件下载
- 运行download.sh将二进制文件下载到本地
- 可设置组件版本, 可设置架构x86_64/aarch64, 默认 x86_64
- aarch64架构: host_arch=aarch64 bash download.sh

### 本地证书生成
```shell
- brew instal cfssl cfssljson
- bash gen_ssl.sh
```

### 下载ansible
```shell
pip3 install ansible netaddr
```

## Ansible Client 节点（远程主机）

### 安装python3
```shell
apt update
apt-get install -y python3
```

### 运行kube-proxy 且ipvs模式
```shell
apt update
apt install -y ipset ipvsadm
```

### 开启etcd自动备份
```shell
apt update
apt install -y cron
```

## 关于apiserver负载均衡
- 请自行实现apiserver的负载均衡, 然后将kube_master_lb写进kube-master/kube-node组的变量中, 示例: https://<kube_master_lb>:6443
- 如果没有设置, 默认每个kube-node启动一个nginx做负载均衡到各master节点

## 默认运行模式
- etcd/kube-apiserver/kube-controller-manager/kube-scheduler 堆叠为一个master节点
- 默认网络插件 cilium 并且运行替代kube-proxy模式
- containerd作为容器运行时
- 默认主机可以从公网拉取镜像

## 不连网主机提前手动拉取镜像
- 可查看images.txt中镜像, 将需要镜像手动打包成: packages/images/${host_arch}/kube-components-images.tar.gz
- kube-node设置变量: offline_pull_images: true

## ca证书
- 证书名强制不能更改, 必须和默认证书名称一致
- 保证自定义的证书能被cfssl识别
