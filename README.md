# Kubernetes on Scaleway

Simple scripts to deploy a kubernetes cluster on [Scaleway](https://www.scaleway.com/en/) using kubeadm.

## Prerequisites

Download the [scaleway cli](https://github.com/scaleway/scaleway-cli), and provide a flexible IP using [the scaleway console](https://console.scaleway.com/instance/ips). Export that IP as `export SCW_FLEX_IP=<your_ip>` and you're ready.

## Getting started

Bootstrap your cluster using `./deploy.sh bootstrap`. For more options run without command or use the `-h` flag.

```sh
./deploy.sh -h
usage: deploy.sh COMMAND [OPTIONS]

Currently the variable SCW_FLEX_IP must be set to a pre-provisioned flexible IP for the master node!

Commands:
  bootstrap   Bootstrap a cluster in mulitple phases (see below)
  start       Start all servers in the cluster. Fails if servers aren't stopped
  stop        Stops all servers in the cluster. Fails if servers aren't running
  delete      Delete all servers in the cluster. Fails if servers aren't stopped
  kubeconfig  Create a kubeconfig for the cluster

Options:
  -h                      Show this help
  -c <node-count>         Set the number of nodes to be created (only: 'bootstrap create-servers')
  -k <version>            Set the kubernetes-version to be used (only: 'bootstrap install-kubeadm')
  -p <bootstrap-phase>    Set the bootstrap phase to be executed, see below

Bootstrap phases (in order of their execution, per default all are executed):
  create-servers              Creates scaleway instances for master and nodes
  start-servers               Starts scaleway instances for master and nodes
  install-kubeadm             Installs kubeadm and required packages on all servers
  init-master                 Initializes the kubernetes master node
  install-core-components     Installs core kubernetes addons (Currently only Calico)
  join-nodes                  Joins nodes to the cluster
```
