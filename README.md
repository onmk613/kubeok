# kubeok

一个基于 Ansible 的 Kubernetes 二进制部署项目，支持 etcd、kube-master、kube-node、常用基础组件（CoreDNS、metrics-server、Cilium/Calico 等）安装与运维。

## 1. 快速开始 | Quick Start

### 1.1 控制机准备（Ansible Server）

```bash
# macOS
brew install ansible cfssl

# Linux
pip3 install ansible netaddr
```

说明:
- 项目默认使用 root 通过 SSH 连接远程主机，配置见 ansible.cfg。
- 需要提前准备好目标节点并确保可 SSH 免密登录。

### 1.2 下载二进制组件

```bash
# 默认 x86_64
bash dowload.sh

# aarch64
host_arch=aarch64 bash dowload.sh
```

说明:
- 下载产物位于 packages/*/${host_arch}。
- 组件版本可以在 dowload.sh 顶部变量中统一调整。

### 1.3 生成本地 CA 证书

```bash
bash gen_ca.sh
```

说明:
- 证书输出目录: packages/ssl。
- 项目内证书文件名是固定约定，不建议改名。

### 1.4 编辑 inventory 并部署

编辑 inventory.yaml，至少配置以下分组:
- etcd
- kube-master
- kube-node

执行部署:

```bash
ansible-playbook -i inventory.yaml playbook.yaml
```

## 2. 特殊配置说明 | Special Configurations

### 2.1 apiserver 负载均衡

方式 1: 外部 LB（推荐）
- 在 kube-master 与 kube-node 组变量中配置 kube_master_lb，例如 https://10.8.2.200:6443。

方式 2: 无外部 LB
- 不设置 kube_master_lb，项目会在每个 kube-node 通过静态 Pod 运行 nginx 代理 kube-apiserver。

### 2.2 网络插件模式

在 all.vars 或 kube-components 变量中配置:

```yaml
network_mode: cilium      # cilium 或 calico
cilium_replace_kube_proxy: true
```

说明:
- 当 cilium_replace_kube_proxy: true 时，不会启动 kube-proxy。

### 2.3 离线镜像导入

将镜像打包放到:
- packages/images/${host_arch}/kube-components-images.tar.gz

并配置:

```yaml
offline_pull_images: true
```

### 2.4 etcd 自动备份

配置:

```yaml
etcd_backup: true
etcd_backup_dir: /var/backups/etcd
```

说明:
- role 会自动安装 cron 并注册每日备份任务。

## 3. 证书更新 | Certificate Renewal

项目已新增:
- playbook-cert-update.yaml: 证书滚动更新 Playbook
- update_certs.sh: 证书更新入口脚本

### 3.1 使用方式

```bash
# 全量更新（etcd -> master -> node）
bash update_certs.sh

# 仅更新 etcd
bash update_certs.sh --group etcd

# 仅更新 kube-master，且只更新某个节点
bash update_certs.sh --group kube-master --limit kube-master-1

# 仅做 dry-run
bash update_certs.sh --group kube-node --dry-run
```

更新策略:
- etcd 与 kube-master 使用 serial: 1 滚动更新，降低不可用风险。
- kube-node 使用 serial: 20% 批量滚动。

## 4. 后期新增节点 | How To Add New Nodes

### 4.1 新增 worker 节点

1. 在 inventory.yaml 的 kube-node 组新增主机。
2. 确保新节点满足前置条件（python3、内核参数、网络连通）。
3. 仅对新节点执行:

```bash
ansible-playbook -i inventory.yaml playbook.yaml --limit <new-node-hostname>
```

### 4.2 新增 master（控制面）节点

1. 在 inventory.yaml 同时补充 kube-master（必要时补充 etcd）。
2. 若使用外部 LB，先把新 master 加入 LB 后端。
3. 分批执行:

```bash
ansible-playbook -i inventory.yaml playbook.yaml --limit <new-master-hostname>
```

4. 验证:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

### 4.3 新增 etcd 节点（谨慎）

建议先做一次备份，再做扩容:
- 先确认现有 etcd 健康。
- 新节点加入 inventory 的 etcd 组。
- 先对新节点 limit 执行，再观察集群状态。
