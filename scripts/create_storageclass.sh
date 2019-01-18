#!/bin/bash

# download all the ICP CLIs

curl -kLo /tmp/cloudctl https://${master_node_url}:8443/api/cli/cloudctl-linux-amd64
sudo mv -f /tmp/cloudctl /usr/local/bin/cloudctl
sudo chmod 755 /usr/local/bin/cloudctl

curl -kLo /tmp/kubectl https://${master_node_url}:8443/api/cli/kubectl-linux-amd64
sudo mv -f /tmp/kubectl /usr/local/bin/kubectl
sudo chmod 755 /usr/local/bin/kubectl

curl -kLo /tmp/helm-linux-amd64.tar.gz https://${master_node_url}:8443/api/cli/helm-linux-amd64.tar.gz
tar -C /tmp -zxvf /tmp/helm-linux-amd64.tar.gz  linux-amd64/helm
sudo mv -f /tmp/linux-amd64/helm /usr/local/bin/helm
sudo chmod 755 /usr/local/bin/helm
rm -rf /tmp/linux-amd64
rm -rf /tmp/helm-linux-amd64.tar.gz

cloudctl login -a https://${master_node_url}:8443 \
  -u admin \
  -p ${icp_password} \
  -c id-${icp_clustername}-account \
  -n default \
  --skip-ssl-validation

# create storage classes for google-pd
cat > /tmp/pd-standard.yaml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: pd-standard
  annotations:
    "storageclass.kubernetes.io/is-default-class": "true"
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
  replication-type: none
EOF


cat > /tmp/pd-ssd.yaml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: pd-ssd
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
  replication-type: none
EOF

cat > /tmp/pd-regional.yaml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: pd-regional
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
  replication-type: regional-pd
EOF


# create the storage classes
kubectl create -f /tmp/pd-standard.yaml
kubectl create -f /tmp/pd-ssd.yaml
kubectl create -f /tmp/pd-regional.yaml

# clean myself up
rm $0
