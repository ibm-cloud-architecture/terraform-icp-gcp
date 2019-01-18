data "google_compute_image" "base_compute_image" {
  project   = "${var.image["project"]}"
  family    = "${var.image["family"]}"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "google_compute_instance" "icp-boot" {
  count        = "${var.boot["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-boot%02d", count.index + 1) }"

  machine_type = "${format("custom-%s-%s", var.boot["cpu"], var.boot["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "icp-boot-${random_id.clusterid.hex}",
    "icp-cluster-${random_id.clusterid.hex}"
  ]

  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.boot["disk_size"]}"
      type = "pd-standard"
    }
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"

    access_config {
      // Ephemeral IP
    }
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}

resource "google_compute_disk" "master_docker" {
  count        = "${var.master["nodes"]}"
  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-master%02d-dockervol", count.index + 1) }"
  type         = "pd-ssd"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"
}

resource "google_compute_instance" "icp-master" {
  count = "${var.master["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-master%02d", count.index + 1) }"
  machine_type = "${format("custom-%s-%s", var.master["cpu"], var.master["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "${compact(list(
    "icp-master-${random_id.clusterid.hex}",
    "${var.proxy["nodes"] < 1 ? "icp-proxy-${random_id.clusterid.hex}" : ""}",
    "icp-cluster-${random_id.clusterid.hex}"
    ))}"
  ]

  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.master["disk_size"]}"
      type = "pd-standard"
    }
  }

  attached_disk {
    source = "${element(google_compute_disk.master_docker.*.self_link, count.index)}"
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
- encoding: b64
  content: ${base64encode("${data.template_file.cloud_provider_conf.rendered}")}
  permissions: '0644'
  path: /etc/cfc/conf/gce.conf
disk_setup:
  /dev/sdb:
     table_type: 'gpt'
     layout: True
     overwrite: True
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
fs_setup:
  - label: None
    filesystem: 'ext4'
    device: '/dev/sdb'
    partition: 'auto'
mounts:
- [ 'sdb', '/var/lib/docker' ]
- [ '${google_filestore_instance.icp-registry.networks.0.ip_addresses.0}:/${google_filestore_instance.icp-registry.file_shares.0.name}', '/var/lib/registry', 'nfs', 'defaults', '0', '0' ]
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["compute-rw", "storage-ro", "logging-write", "monitoring"]
  }
}

resource "google_compute_disk" "worker_docker" {
  count        = "${var.worker["nodes"]}"
  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-worker%02d-dockervol", count.index + 1) }"
  type         = "pd-ssd"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"
}

resource "google_compute_instance" "icp-worker" {
  count = "${var.worker["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-worker%02d", count.index + 1) }"
  machine_type = "${format("custom-%s-%s", var.worker["cpu"], var.worker["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "${compact(list(
    "icp-worker-${random_id.clusterid.hex}",
    "icp-cluster-${random_id.clusterid.hex}"
    ))}"
  ]


  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.worker["disk_size"]}"
      type = "pd-standard"
    }
  }

  attached_disk {
    source = "${element(google_compute_disk.worker_docker.*.self_link, count.index)}"
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
disk_setup:
  /dev/sdb:
     table_type: 'gpt'
     layout: True
     overwrite: True
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
fs_setup:
  - label: None
    filesystem: 'ext4'
    device: '/dev/sdb'
    partition: 'auto'
mounts:
- [ 'sdb', '/var/lib/docker' ]
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["storage-ro", "logging-write", "monitoring"]
  }
}

resource "google_compute_disk" "mgmt_docker" {
  count        = "${var.management["nodes"]}"
  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-mgmt%02d-dockervol", count.index + 1) }"
  type         = "pd-ssd"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"
}

resource "google_compute_instance" "icp-mgmt" {
  count = "${var.management["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-mgmt%02d", count.index + 1) }"
  machine_type = "${format("custom-%s-%s", var.management["cpu"], var.management["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "${compact(list(
    "icp-mgmt-${random_id.clusterid.hex}",
    "icp-cluster-${random_id.clusterid.hex}"
    ))}"
  ]


  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.management["disk_size"]}"
      type = "pd-standard"
    }
  }

  attached_disk {
    source = "${element(google_compute_disk.mgmt_docker.*.self_link, count.index)}"
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
disk_setup:
  /dev/sdb:
     table_type: 'gpt'
     layout: True
     overwrite: True
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
fs_setup:
  - label: None
    filesystem: 'ext4'
    device: '/dev/sdb'
    partition: 'auto'
mounts:
- [ sdb, /var/lib/docker ]
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["storage-ro", "logging-write", "monitoring"]
  }
}

resource "google_compute_disk" "proxy_docker" {
  count        = "${var.proxy["nodes"]}"
  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-proxy%02d-dockervol", count.index + 1) }"
  type         = "pd-ssd"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"
}

resource "google_compute_instance" "icp-proxy" {
  count = "${var.proxy["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-proxy%02d", count.index + 1) }"
  machine_type = "${format("custom-%s-%s", var.proxy["cpu"], var.proxy["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "${compact(list(
    "icp-proxy-${random_id.clusterid.hex}",
    "icp-cluster-${random_id.clusterid.hex}"
    ))}"
  ]


  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.proxy["disk_size"]}"
      type = "pd-standard"
    }
  }

  attached_disk {
    source = "${element(google_compute_disk.proxy_docker.*.self_link, count.index)}"
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
disk_setup:
  /dev/sdb:
     table_type: 'gpt'
     layout: True
     overwrite: True
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
fs_setup:
  - label: None
    filesystem: 'ext4'
    device: '/dev/sdb'
    partition: 'auto'
mounts:
- [ sdb, /var/lib/docker ]
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["storage-ro", "logging-write", "monitoring"]
  }
}

resource "google_compute_disk" "va_docker" {
  count        = "${var.va["nodes"]}"
  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-va%02d-dockervol", count.index + 1) }"
  type         = "pd-ssd"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"
}

resource "google_compute_instance" "icp-va" {
  count = "${var.va["nodes"]}"

  name         = "${format("${lower(var.instance_name)}-${random_id.clusterid.hex}-va%02d", count.index + 1) }"
  machine_type = "${format("custom-%s-%s", var.va["cpu"], var.va["memory"])}"
  zone         = "${element(local.zones, min(length(local.zones) - 1, count.index))}"

  allow_stopping_for_update = true

  tags = [
    "${compact(list(
    "icp-va-${random_id.clusterid.hex}",
    "icp-cluster-${random_id.clusterid.hex}"
    ))}"
  ]

  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.base_compute_image.self_link}"
      size = "${var.va["disk_size"]}"
      type = "pd-standard"
    }
  }

  attached_disk {
    source = "${element(google_compute_disk.va_docker.*.self_link, count.index)}"
  }

  network_interface {
    subnetwork  = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }

  can_ip_forward = true

  metadata_startup_script = <<EOF
${substr(var.image["family"], 0, 4) != "rhel" ? "" : "
#!/bin/bash
yum -y install cloud-init
rm -f /var/log/cloud-init.log
rm -Rf /var/lib/cloud/*
cloud-init -d init
cloud-init -d modules --mode=config
cloud-init -d modules --mode=final
"}
EOF

  metadata {
    sshKeys = <<EOF
${var.ssh_user}:${file(var.ssh_key)}
EOF
    user-data = <<EOF
#cloud-config
write_files:
- encoding: b64
  content: ${base64encode(file("${path.module}/../scripts/bootstrap.sh"))}
  permissions: '0755'
  path: /opt/ibm/scripts/bootstrap.sh
disk_setup:
  /dev/sdb:
     table_type: 'gpt'
     layout: True
     overwrite: True
users:
- name: icpdeploy
  groups: [ wheel ]
  sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
  shell: /bin/bash
  ssh-authorized-keys:
  - ${tls_private_key.ssh.public_key_openssh}
fs_setup:
  - label: None
    filesystem: 'ext4'
    device: '/dev/sdb'
    partition: 'auto'
mounts:
- [ sdb, /var/lib/docker ]
runcmd:
- /opt/ibm/scripts/bootstrap.sh -u icpdeploy ${local.docker_package_uri != "" ? "-p ${local.docker_package_uri}" : "" } -d /dev/sdb
EOF
  }

  service_account {
    email = "${var.service_account_email}"
    scopes = ["storage-ro", "logging-write", "monitoring"]
  }
}
