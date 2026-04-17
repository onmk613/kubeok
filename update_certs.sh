#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# 证书更新入口脚本 | Certificate renewal entry script
# 支持按节点组更新并滚动重启，尽量降低业务抖动。

inventory="inventory.yaml"
group="all"
limit=""
dry_run="false"

usage() {
  cat <<'EOF'
Usage:
  bash update_certs.sh [options]

Options:
  -i, --inventory <file>   Ansible inventory file (default: inventory.yaml)
  -g, --group <name>       Target group: all|etcd|kube-master|kube-node (default: all)
  -l, --limit <pattern>    Optional Ansible --limit pattern
  -n, --dry-run            Run ansible-playbook with --check
  -h, --help               Show this help

Examples:
  bash update_certs.sh
  bash update_certs.sh --group etcd
  bash update_certs.sh --group kube-master --limit kube-master-1
  bash update_certs.sh --group kube-node --limit kube-node-1,kube-node-2
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--inventory)
      inventory="$2"
      shift 2
      ;;
    -g|--group)
      group="$2"
      shift 2
      ;;
    -l|--limit)
      limit="$2"
      shift 2
      ;;
    -n|--dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook not found. Please install ansible first."
  exit 1
fi

if [[ ! -f "$inventory" ]]; then
  echo "Inventory file not found: $inventory"
  exit 1
fi

case "$group" in
  all)
    tags="cert_etcd,cert_master,cert_node"
    ;;
  etcd)
    tags="cert_etcd"
    ;;
  kube-master)
    tags="cert_master"
    ;;
  kube-node)
    tags="cert_node"
    ;;
  *)
    echo "Invalid --group value: $group"
    echo "Allowed values: all|etcd|kube-master|kube-node"
    exit 1
    ;;
esac

cmd=(ansible-playbook -i "$inventory" playbook-cert-update.yaml --tags "$tags")

if [[ -n "$limit" ]]; then
  cmd+=(--limit "$limit")
fi

if [[ "$dry_run" == "true" ]]; then
  cmd+=(--check)
fi

echo "Running: ${cmd[*]}"
"${cmd[@]}"
