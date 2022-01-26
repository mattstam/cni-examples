#!/bin/bash
set -e

# It's entirely possible this is an outdated proceedure, for more recent guide check:
# https://projectcalico.docs.tigera.io/maintenance/enabling-bpf

# # <------------------------------------------------------------------------------------------------->
# echo "SUB: $1";
# echo "RG: $2";
# echo "VMSS: $3";
# echo "NODE_COUNT: $4";
# # <------------------------------------------------------------------------------------------------->

if [  -n "$1" ] && [  -n "$2" ] && [  -n "$3" ] && [  -n "$4" ]; then
    export SUB=$1
    export RG=$2 # MC_mattstam-rg_masq0_westus2 not where the cluster is
    export VMSS=$3
    export NODE_COUNT=$4
fi

if [  -z "$SUB" ] || [  -z "$RG" ] || [  -z "$VMSS" ] || [  -z "$NODE_COUNT" ]; then
    echo "Usage: $0 <subscription-id> <resource-group> <vmss-name> <node-count>"
    exit 1
fi

echo "SUB: $SUB";
echo "RG: $RG";
echo "VMSS: $VMSS";
echo "NODE_COUNT: $NODE_COUNT";

kubectl apply -f ./calico/v3-20-0/operator-base.yaml

export API_SERVER_ENDPOINT=$(kubectl get endpoints kubernetes -o json | jq -r '.subsets[0].addresses[0].ip')
export API_SERVER_PORT=$(kubectl get endpoints kubernetes -o json | jq -r '.subsets[0].ports[0].port')

if [ -z  $API_SERVER_ENDPOINT ] || [ -z $API_SERVER_PORT == "" ]; then
    echo "failed to get apiserver endpoint"
    exit 1
else
    echo "found apiserver endpoint $API_SERVER_ENDPOINT:$API_SERVER_PORT";
    envsubst < ./calico/v3-20-0/install-vxlan-ebpf.yaml > ./calico/v3-20-0/install-vxlan-ebpf-applied.yaml
    kubectl apply -f ./calico/v3-20-0/install-vxlan-ebpf-applied.yaml
fi

export NUM=000000

az vmss run-command invoke \
    --command-id RunShellScript \
    --name $VMSS \
    -g $RG \
    --subscription $SUB \
    --instance-id 0 \
    --scripts `cat <<EOF | sudo tee /etc/systemd/system/sys-fs-bpf.mount
[Unit]
Description=BPF mounts
DefaultDependencies=no
Before=local-fs.target umount.target
After=swap.target

[Mount]
What=bpffs
Where=/sys/fs/bpf
Type=bpf
Options=rw,nosuid,nodev,noexec,relatime,mode=700

[Install]
WantedBy=multi-user.target
EOF` && systemctl daemon-reload && systemctl start sys-fs-bpf.mount && systemctl enable sys-fs-bpf.mount