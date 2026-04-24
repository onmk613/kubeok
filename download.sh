#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# 创建下载包目录
mkdir -p packages || true
cd packages

# 判断操作系统
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v gtar >/dev/null 2>&1 || ! command -v cfssl >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
        echo "Please install the dependencies first: brew install gnu-tar cfssl openssl"
        exit 1
    fi
    TAR_CMD="gtar"
else
    TAR_CMD="tar"
fi

# 判断传入的主机架构
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
etcd_version="v3.6.9"
containerd_version="2.2.2"
runc_version="v1.4.1"
crictl_version="v1.35.0"
kube_version="v1.35.0"
helm_version="v4.1.3"

# releases url
# https://github.com/cloudflare/cfssl/releases
# https://github.com/etcd-io/etcd/releases
# https://github.com/containerd/containerd/releases
# https://github.com/opencontainers/runc/releases
# https://github.com/kubernetes-sigs/cri-tools/releases

# https://github.com/kubernetes/kubernetes/releases
# test: https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kube-apiserver

# https://github.com/helm/helm/releases
# test: https://get.helm.sh/helm-v4.1.3-linux-amd64.tar.gz

# cfssl download
download_cfssl_binary() {
    mkdir -p cfssl/${host_arch}
    local_arch=$(uname -m)
    local_kernel=$(uname -s)
    if ${local_arch} != ${host_arch} && ${local_kernel} == "Linux"; then
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_amd64 -O cfssl/x86_64/cfssl
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_amd64 -O cfssl/x86_64/cfssljson
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_arm64 -O cfssl/aarch64/cfssl
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_arm64 -O cfssl/aarch64/cfssljson
    else
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssl_${cfssl_version}_linux_${host_arch_alias} -O cfssl/${host_arch}/cfssl
        wget https://github.com/cloudflare/cfssl/releases/download/v${cfssl_version}/cfssljson_${cfssl_version}_linux_${host_arch_alias} -O cfssl/${host_arch}/cfssljson
    fi
}

# etcd download
download_etcd_binary() {
    wget https://github.com/etcd-io/etcd/releases/download/${etcd_version}/etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz
    mkdir -p etcd/${host_arch}
    $TAR_CMD -xf etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz -C etcd/${host_arch} --strip-components=1 --wildcards '*/etcd' '*/etcdctl' '*/etcdutl'
    rm -f etcd-${etcd_version}-linux-${host_arch_alias}.tar.gz
}

# container runtime download
download_containerd_binary() {
    wget https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz
    mkdir -p containerd/${host_arch}
    wget https://github.com/opencontainers/runc/releases/download/${runc_version}/runc.${host_arch_alias} -O containerd/${host_arch}/runc
    $TAR_CMD -xf containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz -C containerd/${host_arch}/ --strip-components=1
    rm -f containerd-${containerd_version}-linux-${host_arch_alias}.tar.gz
}

# kube and crictl download
download_kube_binary() {
    mkdir -p kube/${host_arch}
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-apiserver -O kube/${host_arch}/kube-apiserver
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-controller-manager -O kube/${host_arch}/kube-controller-manager
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-scheduler -O kube/${host_arch}/kube-scheduler
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kubectl -O kube/${host_arch}/kubectl
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kubelet -O kube/${host_arch}/kubelet
    wget https://dl.k8s.io/release/${kube_version}/bin/linux/${host_arch_alias}/kube-proxy -O kube/${host_arch}/kube-proxy

    # helm 下载
    wget https://get.helm.sh/helm-${helm_version}-linux-${host_arch_alias}.tar.gz -O helm-${helm_version}-linux-${host_arch_alias}.tar.gz
    $TAR_CMD -xf helm-${helm_version}-linux-${host_arch_alias}.tar.gz  -C kube/${host_arch}/ --strip-components=1 --wildcards '*/helm'
    rm -f helm-${helm_version}-linux-${host_arch_alias}.tar.gz

    # crictl 下载
    wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${crictl_version}/crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz
    $TAR_CMD -xf crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz -C kube/${host_arch}/
    rm -f crictl-${crictl_version}-linux-${host_arch_alias}.tar.gz
}

gen_ssl() {
    mkdir -p packages/ssl || true
    cd packages/ssl

    cat <<EOF | tee ca-csr.json
{
  "CN": "kubernetes and etcd",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "CN",
      "ST": "SiChuan",
      "L": "ChengDu",
      "O": "kubernetes and etcd System",
      "OU": "kubernetes and etcd Security"
    }
  ],
  "ca": {
    "expiry": "876000h"
  }
}
EOF

    cat <<EOF | tee ca-config.json
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF

    # 生成证书
    if ! command -v cfssl >/dev/null 2>&1 || ! command -v cfssljson >/dev/null 2>&1; then
        ../cfssl/${host_arch}/cfssl gencert -initca ca-csr.json | ../cfssl/${host_arch}/cfssljson -bare k8s-ca
        ../cfssl/${host_arch}/cfssl gencert -initca ca-csr.json | ../cfssl/${host_arch}/cfssljson -bare etcd-ca
    else
        cfssl gencert -initca ca-csr.json | cfssljson -bare k8s-ca
        cfssl gencert -initca ca-csr.json | cfssljson -bare etcd-ca
        openssl x509 -in k8s-ca.pem -text -noout
        openssl x509 -in etcd-ca.pem -text -noout
    fi

    rm -f k8s-ca.csr etcd-ca.csr
    cd -
}

# Main execution
download_cfssl_binary
download_etcd_binary
download_containerd_binary
download_kube_binary
gen_ssl
