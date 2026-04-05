#!/bin/bash

set -e
set -x

# 创建临时目录并进入
rm -rf /tmp/kube-master
mkdir -p /tmp/kube-master
cd /tmp/kube-master

if [ -z ${cluster_ip} ] || [ -z ${kube_cert_dir} ] || [ -z ${kube_master_ip} ] || [ -z ${kube_master_lb} ] || [ -z ${kube_apiserver_port} ]; then
  echo "请设置 cluster_i、kube_cert_dir、kube_master_ip、kube_apiserver_port 和 kube_master_lb 环境变量"
  exit 1
fi

kube_master_endpoint="https://${kube_master_ip}:${kube_apiserver_port}"

# services_cidr=10.96.0.0/16
# services=(${services_cidr//./ })
# service_prefix=${services[0]}"."${services[1]}"."${services[2]}
# KUBERNETES_IP=${service_prefix}.1

# 只去kube_master_lb的host部分, 写入证书
lb_temp="${kube_master_lb#*://}"
kube_master_lb_host="${lb_temp%%:*}"

# 配置证书hosts
# 如果有多个lb地址可以通过空格区分
# 例如: kube_master_lb="myk8s.com mylan.com 192.168.0.99"
cluster_domain="${cluster_domain:-cluster.local}"
d_temp="${kube_master_lb#*://}"
cluster_domain_host="${d_temp%%:*}"

HOSTS=(
    "127.0.0.1"
    "${cluster_ip}"
    "${kube_master_ip}"
    "${kube_master_lb_host}"
    "kubernetes"
    "${cluster_domain_host}"
    "kubernetes.default"
    "kubernetes.default.svc"
    "kubernetes.default.svc.cluster.local"
    "kubernetes.default.svc.${cluster_domain_host}"
)
# 使用 sort -u 去重合并
HOSTS_JSON=$(printf '"%s"\n' "${HOSTS[@]}" | sort -u | sed '/^"$/d' | paste -sd ',' -)

# etcd 证书 csr json 文件
cat <<EOF | tee etcd-client-csr.json
{
  "CN": "etcd client",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "CN",
      "ST": "SiChuan",
      "L": "ChengDu",
      "O": "Kubernetes",
      "OU": "etcd"
    }
  ]
}
EOF

# kube-apiserver 证书 csr json 文件
cat <<EOF | tee kubernetes-csr.json
{
  "CN": "kubernetes",
  "hosts": [${HOSTS_JSON}],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "CN",
      "ST": "SiChuan",
      "L": "ChengDu",
      "O": "Kubernetes",
      "OU": "kube-apiserver"
    }
  ]
}
EOF

# front-proxy-client 证书 csr json 文件
cat <<EOF | tee front-proxy-client-csr.json
{
  "CN": "front-proxy-client",
  "hosts": [
      "127.0.0.1",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "CN",
      "ST": "SiChuan",
      "L": "ChengDu",
      "O": "Kubernetes",
      "OU": "front-proxy-client Security"
    }
  ]
}
EOF

# kube-controller-manager 证书 csr json 文件
cat <<EOF | tee kube-controller-manager-csr.json
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes",
      "ST": "Oregon"
    }
  ]
}
EOF

# kube-scheduler 证书 csr json 文件
cat <<EOF | tee kube-scheduler-csr.json
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes",
      "ST": "Oregon"
    }
  ]
}
EOF

# admin(kubectl) 证书 csr json 文件
cat <<EOF | tee admin-csr.json
{
  "CN": "admin",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:masters",
      "OU": "Kubernetes",
      "ST": "Oregon"
    }
  ]
}
EOF

# 生成 etcd 证书
cfssl gencert \
  -ca=${kube_cert_dir}/etcd-ca.pem \
  -ca-key=${kube_cert_dir}/etcd-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./etcd-client-csr.json | cfssljson -bare etcd-client

# kube-apiserver 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./kubernetes-csr.json | cfssljson -bare kubernetes

# front-proxy-client 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./front-proxy-client-csr.json | cfssljson -bare front-proxy-client

# kube-controller-manager 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

# kube-scheduler 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./kube-scheduler-csr.json | cfssljson -bare kube-scheduler

# admin(kubectl) 证书
cfssl gencert \
  -ca=${kube_cert_dir}/k8s-ca.pem \
  -ca-key=${kube_cert_dir}/k8s-ca-key.pem \
  -config=${kube_cert_dir}/ca-config.json \
  -profile=kubernetes \
  ./admin-csr.json | cfssljson -bare admin

# 创建 kube-controller-manager 的 kubeconfig 文件
{
  kubectl config set-cluster kubernetes \
    --certificate-authority=${kube_cert_dir}/k8s-ca.pem \
    --embed-certs=true \
    --server=${kube_master_endpoint} \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}

# 生成kube-scheduler.kubeconfig文件
{
  kubectl config set-cluster kubernetes \
    --certificate-authority=${kube_cert_dir}/k8s-ca.pem \
    --embed-certs=true \
    --server=${kube_master_endpoint} \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

# 生成admin.kubeconfig(kubectl)文件
{
  kubectl config set-cluster kubernetes \
    --certificate-authority=${kube_cert_dir}/k8s-ca.pem \
    --embed-certs=true \
    --server=${kube_master_endpoint} \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

# 生成 service-account的证书
/bin/cp -rf ${kube_cert_dir}/k8s-ca.pem sa.pem
/bin/cp -rf ${kube_cert_dir}/k8s-ca-key.pem sa-key.pem

# 移动证书到指定目录
mv *.pem ${kube_cert_dir}/
mv kube-controller-manager.kubeconfig ${kube_cert_dir}/
mv kube-scheduler.kubeconfig ${kube_cert_dir}/
mkdir -p ${HOME}/.kube
mv admin.kubeconfig ${HOME}/.kube/config

# 清理临时目录
cd ..
rm -rf /tmp/kube-master
