#!/bin/bash

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

cfssl gencert -initca ca-csr.json | cfssljson -bare k8s-ca
cfssl gencert -initca ca-csr.json | cfssljson -bare etcd-ca
rm -f k8s-ca.csr etcd-ca.csr
openssl x509 -in k8s-ca.pem -text -noout
openssl x509 -in etcd-ca.pem -text -noout

cd -
