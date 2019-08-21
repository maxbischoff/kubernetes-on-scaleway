#!/bin/bash

set -e
source ./helpers.sh
ACTION="${1}"

function show_help {
    echo "usage: $(basename ${0}) COMMAND [OPTIONS]"
    echo
    echo "Set the variable MASTER_FLEX_IP to a pre-provisioned flexible IP to ensure that it is not changed after a reboot."
    echo "You can also apply flex-IPs for worker nodes with environment variables NODE_x_FLEX_IP where x is the worker node number."
    echo
    echo "Commands:"
    echo "  bootstrap   Bootstrap a cluster in mulitple phases (see below)"
    echo "  start       Start all servers in the cluster. Fails if servers aren't stopped"
    echo "  stop        Stops all servers in the cluster. Fails if servers aren't running"
    echo "  delete      Delete all servers in the cluster. Fails if servers aren't stopped"
    echo "  kubeconfig  Create a kubeconfig for the cluster"
    echo
    echo "Options:"
    echo "  -h                      Show this help"
    echo "  -c <node-count>         Set the number of nodes to be created (only: 'bootstrap create-servers')"
    echo "  -k <version>            Set the kubernetes-version to be used (only: 'bootstrap install-kubeadm')"
    echo "  -p <bootstrap-phase>    Set the bootstrap phase to be executed, see below"
    echo
    echo "Bootstrap phases (in order of their execution, per default all are executed):"
    echo "  create-servers              Creates scaleway instances for master and nodes"
    echo "  start-servers               Starts scaleway instances for master and nodes"
    echo "  install-kubeadm             Installs kubeadm and required packages on all servers"
    echo "  init-master                 Initializes the kubernetes master node"
    echo "  install-core-components     Installs core kubernetes addons (Currently only Calico)"
    echo "  join-nodes                  Joins nodes to the cluster"
    exit 1
}

if [ -z "${1}" ]; then
    show_help
fi

node_count=1
kubernetes_version="v1.15.0"
docker_version="18.06.2"
bootstrap_phase=
cluster_name="k8s"

while getopts "h?c:k:p:n:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    c)  node_count=$OPTARG
        ;;
    k)  kubernetes_version=$OPTARG
        ;;
    p)  bootstrap_phase=$OPTARG
        ;;
    n)  cluster_name=$OPTARG
        ;;
    esac
done

INIT_ARGS="--pod-network-cidr=192.168.0.0/16"
COMMON_TAGS="k8s-cluster=${cluster_name}"

# main functions
function start_all {
    scw start $(scw ps -a | grep ${cluster_name}- | awk '{print $1}')
}

function stop_all {
    echo "Stopping all nodes"
    scw stop $(scw ps -a | grep ${cluster_name}- | awk '{print $1}')
    wait_for_state stopped ${cluster_name}
}

function create_nodes {
    echo "Creating one master and ${node_count} worker nodes."
    echo ${COMMON_TAGS} > ./tmp/common_tags
    scw create --name="${cluster_name}-master" --ip-address="${MASTER_FLEX_IP:-dynamic}" \
        --commercial-type="DEV1-S" --env="${COMMON_TAGS} role=master" f974feac > ./tmp/master_id
    for ((i=0;i<=node_count-1;i++)); do
        varname=NODE_${node_num}_FLEX_IP
        ip_address=${!varname:-dynamic}
        if ip_address != "dynamic"; then
            echo "Using IP address ${ip_address} for worker node $i"
        fi
        # currently dynamic ip address is required to install stuff from the internet
        scw create --name="${cluster_name}-node-${i}" --ip-address=${ip_address} \
         --commercial-type="DEV1-S" --env="${COMMON_TAGS} role=master" f974feac > ./tmp/node_${i}_id
    done
}

function bootstrap {
    create_nodes
    echo "Nodes created, starting now."
    start_all
    echo "Waiting for nodes to come up"
    wait_for_state "running" ${cluster_name}
    echo "Sleeping 1m to let nodes be fully started"
    sleep 60
    install_kubeadm
    init_master
    install_core_kube_addons
    join_nodes
}

function delete_all {
    echo "Deleting all ${cluster_name}- servers"
    scw rm $(scw ps -a | grep ${cluster_name}- | awk '{print $1}')
}

function create_kubeconfig {
    master_ip=$(get_master_ip)
    # scw cp didn't work here, so we use scp directly
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
        root@${master_ip}:/etc/kubernetes/admin.conf ./kubeconfig > tmp/kubeconfig.log
    kubectl --kubeconfig=./kubeconfig config set \
        clusters.kubernetes.server https://${master_ip}:6443 >> tmp/kubeconfig.log
    echo "Stored kubeconfig to ./kubeconfig set following environment variable to use it:"
    echo
    echo "  export KUBECONFIG=$(pwd)/kubeconfig"
    echo
}

function main {
    mkdir -p ./tmp

    if [ ! -z ${bootstrap_phase} ] && [ "${1}" != "bootstrap" ]; then
        echo "'-b' can only be used in conjunction with ${0} bootstrap"
        show_help
    fi

    if [ "${1}" == "bootstrap" ]; then
        if $(scw ps -a | grep -q '${cluster_name}-'); then
            echo "Found k8s nodes, aborting bootstrap. Delete them using ${0} delete"
            echo "Found nodes:"
            scw ps -a | grep -e k8s --color=never
            echo
        else
            if [ ! -z ${bootstrap_phase} ]; then
                bootstrap
            elif [ "create-servers" == "${bootstrap_phase}" ]; then
                create_nodes
            elif [ "start-servers" == "${bootstrap_phase}" ]; then
                start_all
            elif [ "install-kubeadm" == "${bootstrap_phase}" ]; then
                install_kubeadm
            elif [ "init-master" == "${bootstrap_phase}" ]; then
                init_master
            elif [ "install-core-components" == "${bootstrap_phase}" ]; then
                install_core_kube_addons
            elif [ "join-nodes" == "${bootstrap_phase}" ]; then
                join_nodes
            else
                echo "Unsupported phase ${bootstrap_phase}"
                exit 1
            fi
        fi
    elif [ "${1}" == "delete" ]; then
        if $(scw ps -a | grep -q '${cluster_name}-'); then
            delete_all
            # todo delete volumes (list with scw images -f type=volume --region= ...)
            rm -r tmp
        else
            echo "Nothing to delete"
        fi
    elif [ "${1}" == "install" ]; then
        install_kubeadm
    elif [ "${1}" == "start" ]; then
        start_all
    elif [ "${1}" == "stop" ]; then
        stop_all
    elif [ "${1}" == "kubeconfig" ]; then
        create_kubeconfig
    else
        echo "Error: unknown command or no command was provided"
        show_help
    fi
}

main $ACTION
