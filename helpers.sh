
function get_master_ip {
    scw inspect -f "{{ .PublicAddress.IP }}" $(cat ./tmp/master_id)
}

function exec_master {
    user=${EXEC_USER:-"root"}
    echo "Running '${@}' on master node as user ${user}"
    scw exec -w --user ${user} $(cat ./tmp/master_id) ${@}
}

function node_id () {
    node_num=${1}
    echo $(cat ./tmp/node_${node_num}_id)
}

function exec_all_nodes {
    user=${EXEC_USER:-"root"}
    for ((i=0;i<=node_count-1;i++)); do
        echo "Running '${@}' on node ${i} as user ${user}"
        scw exec -w --user ${user} $(node_id ${i}) ${@}
    done
}

function wait_for_state {
    state=${1}
    cluster_name=${2}
    while [ $(scw ps -a | grep ${cluster_name}- | grep -c "${state}") -lt ${node_count} ];
        do sleep 5 ;
    done
}

function install_kubeadm {
    target="$(cat ./tmp/master_id):/usr/sbin/"
    scw cp $(pwd)/master_scripts ${target}
    for ((i=0;i<=node_count-1;i++)); do
        target="$(node_id ${i}):/usr/sbin/"
        scw cp $(pwd)/master_scripts ${target}
    done
    exec_master /usr/sbin/master_scripts/install_docker.sh ${docker_version} | tee tmp/master_docker.log
    exec_master /usr/sbin/master_scripts/install_kubeadm.sh ${kubernetes_version} | tee tmp/master_kubeadm.log
    exec_all_nodes /usr/sbin/master_scripts/install_docker.sh ${docker_version} | tee tmp/nodes_docker.log
    exec_all_nodes /usr/sbin/master_scripts/install_kubeadm.sh ${kubernetes_version} | tee tmp/nodes_kubeadm.log
}

function install_core_kube_addons {
    exec_master kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
}

function init_master {
    master_private_ip=$(scw inspect -f "{{ .PrivateIP }}" $(cat ./tmp/master_id))
    INIT_ARGS="${INIT_ARGS} --apiserver-advertise-address ${master_private_ip}"
    INIT_ARGS="${INIT_ARGS} --apiserver-cert-extra-sans ${SCW_FLEX_IP}"
    exec_master kubeadm init ${INIT_ARGS} | tee tmp/master_kubeadminit.log
}

function join_nodes {
    exec_master kubeadm token create --print-join-
    mmand > tmp/join_command
    # remove ^M that appears in our file https://unix.stackexchange.com/questions/134695/what-is-the-m-character-called
    perl -p -i -e "s/\r//g" tmp/join_command
    exec_all_nodes $(cat tmp/join_command | grep "kubeadm join") | tee tmp/node_kubeadmjoin.log
}
