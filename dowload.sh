#！/bin/bash

set -o nounset
set -o errexit
set -o pipefail

mkdir -p packages || true
cd packages

if [[ "$OSTYPE" == "darwin"* ]]; then
    TAR_CMD="gtar"
else
    TAR_CMD="tar"
fi

# Set architecture environment variables
set_arch_env() {
    host_arch="${host_arch:-x86_64}"
    case "$host_arch" in
        "x86_64")
            host_arch_alias="amd64"
            ;;
        "aarch64")
            host_arch_alias="arm64"
            ;;
        *)
            echo "Error: Unsupported architecture '$host_arch'. Only x86_64 and aarch64 are allowed."
            return 1
            ;;
    esac
}
set_arch_env || exit 1

cfssl_version="1.6.5"
# etcd version >= 3.4.0
etcd_version="v3.6.9"
containerd_version="2.2.2"
runc_version="v1.4.1"
crictl_version="v1.35.0"
kube_version="v1.35.0"

# cfssl download
# https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64
# https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64
download_cfssl_binary() {
    mkdir -p cfssl/${host_arch}
    wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_${host_arch_alias} -O cfssl/${host_arch}/cfssl
    wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_${host_arch_alias} -O cfssl/${host_arch}/cfssljson
}

# etcd download
# https://github.com/etcd-io/etcd/releases/download/v3.6.9/etcd-v3.6.9-linux-amd64.tar.gz
download_etcd_binary() {
    wget https://github.com/etcd-io/etcd/releases/download/${etcd_version}/etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz
    mkdir -p etcd/${host_arch}
    $TAR_CMD -xf etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz -C etcd/${host_arch} --strip-components=1 --wildcards '*/etcd' '*/etcdctl' '*/etcdutl'
    rm -f etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz
}

# container runtime download
# https://github.com/containerd/containerd/releases/download/v2.2.2/containerd-2.2.2-linux-amd64.tar.gz
# https://github.com/opencontainers/runc/releases/download/v1.3.5/runc.arm64
download_containerd_binary() {
    wget https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz
    mkdir -p containerd/${host_arch}
    wget https://github.com/opencontainers/runc/releases/download/${runc_version}/runc.${host_arch_alias} -O containerd/${host_arch}/runc
    $TAR_CMD -xf containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz -C containerd/${host_arch}/ --strip-components=1
    rm -f containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz
}

# kube and crictl download
# https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/xxx
# https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.35.0/crictl-v1.35.0-linux-amd64.tar.gz
download_kube_binary() {
    mkdir -p kube/${host_arch}
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-apiserver -O kube/${host_arch}/kube-apiserver
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-controller-manager -O kube/${host_arch}/kube-controller-manager
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-scheduler -O kube/${host_arch}/kube-scheduler
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kubectl -O kube/${host_arch}/kubectl
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kubeadm -O kube/${host_arch}/kubeadm
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kubelet -O kube/${host_arch}/kubelet
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-proxy -O kube/${host_arch}/kube-proxy
    wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${crictl_version}/crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz
    $TAR_CMD -xf crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz -C kube/${host_arch}/
    rm -f crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz
}

download_required_components() {
    docker pull --platform linux/ ${host_arch_alias} nginx:1.24.0
}

# Main execution
download_etcd_binary
download_containerd_binary
download_kube_binary
download_cfssl_binary

# 下载必要组件镜像, pause, coredns, metrics-server
# 网络插件(可选): flannel/calico/cilium
# ingress(可选): nginx/traefik
# 监控(可选): prometheus
# download_required_components
