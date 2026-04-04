#!/bin/bash

set -e
set -x

# 创建临时目录并进入
mkdir -p /tmp/kube-node
cd /tmp/kube-node

if [ -z ${kube_cert_dir} ] || [ -z ${kube_master_endpoint} ]; then
  echo "请设置 kube_cert_dir 和 kube_master_endpoint 环境变量"
  exit 1
fi

# kube-proxy 证书 csr json 文件
cat <<EOF | tee kube-proxy-csr.json
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-proxy",
      "OU": "Kubernetes",
      "ST": "Oregon"
    }
  ]
}
EOF

# kube-proxy 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./kube-proxy-csr.json | cfssljson -bare kube-proxy

# 生成 kube-proxy.kubeconfig 文件
{
  kubectl config set-cluster kubernetes \
    --certificate-authority=${kube_cert_dir}/k8s-ca.pem \
    --embed-certs=true \
    --server=${kube_master_endpoint} \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

# 复制证书到指定目录
mv *.pem ${kube_cert_dir}/
cp kube-proxy.kubeconfig ${kube_cert_dir}/

# 清理临时目录
cd ..
rm -rf /tmp/kube-node
