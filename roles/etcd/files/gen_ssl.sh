#!/bin/bash

set -e
set -x

# 创建临时目录并进入
mkdir -p /tmp/etcd
cd /tmp/etcd

if [ -z ${etcd_internal_ip} ] || [ -z ${etcd_lb} ] || [ -z ${etcd_cert_dir} ]; then
  echo "请设置 etcd_internal_ip、etcd_lb 和 etcd_cert_dir 环境变量"
  exit 1
fi

# 生成etcd集群证书配置文件
cat <<EOF | tee etcd-csr.json
{
  "CN": "etcd cluster",
  "hosts": [
      "127.0.0.1",
      "${etcd_internal_ip}",
      "${etcd_lb}"
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
      "OU": "etcd"
    }
  ]
}
EOF

# 生成 etcd 证书
cfssl gencert \
  -ca=${etcd_cert_dir}/etcd-ca.pem \
  -ca-key=${etcd_cert_dir}/etcd-ca-key.pem \
  -config=${etcd_cert_dir}/ca-config.json \
  -profile=kubernetes ./etcd-csr.json | cfssljson -bare etcd

# 移动证书到指定目录
mv etcd*.pem ${etcd_cert_dir}

# 清理临时目录
cd ..
rm -rf /tmp/etcd
