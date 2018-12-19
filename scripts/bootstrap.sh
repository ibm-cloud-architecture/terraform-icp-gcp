#!/bin/bash

exec &> >(tee -a /tmp/bootstrap.log)

ubuntu_install(){
  # attempt to retry apt-get update until cloud-init gives up the apt lock
  until apt-get update; do
    sleep 2
  done

  until apt-get install -y \
    unzip \
    python \
    python-yaml \
    thin-provisioning-tools \
    pv \
    nfs-client \
    lvm2; do
    sleep 2
  done
}

crlinux_install() {
  yum install -y \
    unzip \
    PyYAML \
    device-mapper \
    libseccomp \
    libtool-ltdl \
    libcgroup \
    iptables \
    device-mapper-persistent-data \
    nfs-utils \
    lvm2
}

docker_install() {
  if docker --version; then
    echo "Docker already installed. Exiting"
    return 0
  fi

  if [ -z "${package_location}" -a "${OSLEVEL}" == "ubuntu" ]; then
    # if we're on ubuntu, we can install docker-ce off of the repo
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

    add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"

    apt-get update && apt-get install -y docker-ce
  elif [ ! -z "${package_location}" ]; then
    if [[ "${package_location:0:2}" == "gs" ]]; then
      gsutil cp ${package_location} /tmp/$(basename ${package_location})
      package_location=/tmp/$(basename ${package_location})
    fi

    echo "Install docker from ${package_location}"
    chmod u+x "${package_location}"

    # loop here until file provisioner is done copying the package
    until ${package_location} --install; do
      sleep 2
    done
  else
    return 0
  fi

  partprobe
  lsblk

  systemctl enable docker

  storage_driver=`docker info | grep 'Storage Driver:' | cut -d: -f2 | sed -e 's/\s//g'`
  echo "storage driver is ${storage_driver}"
  if [ "${storage_driver}" == "devicemapper" ]; then
    systemctl stop docker

    # remove storage-driver from docker cmdline
    sed -i -e '/ExecStart/ s/--storage-driver=devicemapper//g' /usr/lib/systemd/system/docker.service

    # docker installer uses devicemapper already; switch to overlay2
    cat > /tmp/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
    mv /tmp/daemon.json /etc/docker/daemon.json

    systemctl daemon-reload
  fi

  gpasswd -a ${docker_user} docker
  systemctl restart docker

  # docker takes a while to start because it needs to prepare the
  # direct-lvm device ... loop here until it's running
  _count=0
  systemctl is-active docker | while read line; do
    if [ ${line} == "active" ]; then
      break
    fi

    echo "Docker is not active yet; waiting 3 seconds"
    sleep 3
    _count=$((_count+1))

    if [ ${_count} -gt 10 ]; then
      echo "Docker not active after 30 seconds"
      return 1
    fi
  done

  echo "Docker is installed."
  docker info

}

##### MAIN #####
while getopts ":p:d:i:s:u:" arg; do
    case "${arg}" in
      p)
        package_location=${OPTARG}
        ;;
      d)
        docker_disk=${OPTARG}
        ;;
      u)
        docker_user=${OPTARG}
        ;;
    esac
done

#Find Linux Distro
OSLEVEL=other
if grep -q -i ubuntu /etc/*release; then
    OSLEVEL=ubuntu
fi
echo "Operating System is $OSLEVEL"

# pre-reqs
if [ "$OSLEVEL" == "ubuntu" ]; then
  ubuntu_install
else
  crlinux_install
fi

docker_install

# TODO try mount -a a few times until filestore mounts
mount -a

mkdir -p /opt/ibm
touch /opt/ibm/.bootstrap_complete

echo "Complete.."
