#!/bin/bash


# only run this script on ICP versions < 3.1.1
icp_version=`basename ${icp_installer} | cut -d: -f2 | sed -e 's/-ee//g'`
execute=`awk 'BEGIN {if('$${icp_version}' > 3.1.0) {print "false";} else {print "true";}}'`

if [ "$${execute}" != "true" ]; then
  echo "ICP version $${icp_version}, not modifying calico config ..."
  exit 0
fi

echo "ICP version $${icp_version}, modifying calico config to disable Calico IPAM ..."

kubectl get configmaps \
  -n kube-system \
  calico-config  \
  -o template \
  --template '{{.data.cni_network_config}}' > /tmp/cni_network_config.json.bak

export jq="docker run --rm -i -v /tmp:/tmp:z --entrypoint jq stedolan/jq"

cat cni_network_config.json.bak | $${jq} -c '. | .plugins[0].ipam.type |= "host-local" | .plugins[0].ipam.subnet |= "usePodCidr"' > /tmp/cni_network_config.json
kubectl get configmaps   -n kube-system   calico-config  --export  -o json | $${jq} '.data.calico_backend |= "none" | .data.cni_network_config |= ('`cat /tmp/cni_network_config.json`' | tojson) ' > /tmp/calico-config.json

kubectl apply -f /tmp/calico-config.json

# restart calico
kubectl delete pods -n kube-system -l app=calico-node

kubectl rollout status -n kube-system ds/calico-node

# restart all pods in kube-system
kubectl get pods -n kube-system  | \
  awk '{print $1;}' | \
  grep -v '^NAME$' | \
  grep -v k8s | \
  grep -v calico-node | \
  xargs kubectl delete pods -n kube-system --wait=false
