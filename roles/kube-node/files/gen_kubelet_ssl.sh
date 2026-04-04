#!/bin/bash

set -e
set -x

# 创建临时目录并进入
mkdir -p /tmp/kube-node
cd /tmp/kube-node

if [ -z ${kube_cert_dir} ] || [ -z ${kube_master_endpoint} ] || [ -z ${kube_node_ip} ]|| [ -z ${kube_node_name} ]; then
  echo "请设置 kube_cert_dir、kube_master_endpoint、kube_node_ip 和 kube_node_name 环境变量"
  exit 1
fi

# 配置证书hosts
HOSTS=(
    "127.0.0.1"
    "${kube_node_ip}"
    "${kube_node_name}"
)
# 使用 sort -u 去重合并
HOSTS_JSON=$(printf '"%s"\n' "${HOSTS[@]}" | sort -u | sed '/^"$/d' | paste -sd ',' -)

# kubelet 证书 csr json 文件
cat <<EOF | tee kubelet-csr.json
{
  "CN": "system:node:${kube_node_name}",
  "hosts": [${HOSTS_JSON}],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "O": "system:nodes",
      "OU": "Kubernetes",
      "ST": "Oregon"
    }
  ]
}
EOF

# kubelet 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./kubelet-csr.json | cfssljson -bare kubelet-${kube_node_name}

# 生成 kubelet.kubeconfig 文件
{
  kubectl config set-cluster kubernetes \
    --certificate-authority=${kube_cert_dir}/k8s-ca.pem \
    --embed-certs=true \
    --server=${kube_master_endpoint} \
    --kubeconfig=kubelet.kubeconfig

  kubectl config set-credentials system:node:${kube_node_name} \
    --client-certificate=kubelet-${kube_node_name}.pem \
    --client-key=kubelet-${kube_node_name}-key.pem \
    --embed-certs=true \
    --kubeconfig=kubelet.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes \
    --user=system:node:${kube_node_name} \
    --kubeconfig=kubelet.kubeconfig

  kubectl config use-context default --kubeconfig=kubelet.kubeconfig
}

# 复制证书到指定目录
mv *.pem ${kube_cert_dir}/
cp kubelet.kubeconfig ${kube_cert_dir}/

# 清理临时目录
cd ..
rm -rf /tmp/kube-node
