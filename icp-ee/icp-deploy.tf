##########################################
### Load the ICP Enterprise images tarball
## This is skipped if installing from
## external private registry
##########################################
resource "null_resource" "image_load" {
  # Only do an image load if we have provided a location. Presumably if not we'll be loading from private registry server

  connection {
    host          = "${google_compute_instance.icp-boot.network_interface.0.network_ip }"
    user          = "icpdeploy"
    private_key   = "${tls_private_key.ssh.private_key_pem}"
    bastion_host  = "${google_compute_instance.icp-boot.network_interface.0.access_config.0.nat_ip }"
  }

  provisioner "file" {
    source = "${path.module}/../scripts/load_image.sh"
    destination = "/tmp/load_image.sh"
  }

  provisioner "remote-exec" {
    # We need to wait for cloud init to finish it's boot sequence.
    inline = [
      "while [ ! -f /opt/ibm/.bootstrap_complete ]; do sleep 1; done",
      "export REGISTRY_USERNAME=${local.docker_username}",
      "export REGISTRY_PASSWORD=${local.docker_password}",
      "sudo mv /tmp/load_image.sh /opt/ibm/scripts/",
      "sudo chmod a+x /opt/ibm/scripts/load_image.sh",
      "/opt/ibm/scripts/load_image.sh ${var.image_location != "" ? "-p ${var.image_location}" : ""} -r ${local.registry_server} -c ${local.docker_password}",
      "sudo touch /opt/ibm/.imageload_complete"
    ]
  }
}

resource "null_resource" "cert_copy" {
  # copy the CA certs, if they exist
  depends_on = ["null_resource.image_load"]

  connection {
    host          = "${google_compute_instance.icp-boot.network_interface.0.network_ip}"
    user          = "icpdeploy"
    private_key   = "${tls_private_key.ssh.private_key_pem}"
    bastion_host  = "${google_compute_instance.icp-boot.network_interface.0.access_config.0.nat_ip}"
  }

  provisioner "remote-exec" {
    # We need to wait for cloud init to finish it's boot sequence.
    inline = [
      "mkdir -p /tmp/cfc-certs"
    ]
  }

  provisioner "file" {
    source = "${path.module}/../cfc-certs/"
    destination = "/tmp/cfc-certs"
  }

  provisioner "remote-exec" {
    # We need to wait for cloud init to finish it's boot sequence.
    inline = [
      "sudo mkdir -p /opt/ibm/cluster",
      "sudo mv /tmp/cfc-certs /opt/ibm/cluster"
    ]
  }
}

data "template_file" "cloud_provider_conf" {
  template = <<EOF
[global]
project-id = ${data.google_project.icp_project.id}
network-project-id = ${google_compute_network.icp_vpc.project}
network-name = ${google_compute_network.icp_vpc.name}
subnetwork-name = ${google_compute_subnetwork.icp_region_subnet.name}
node-instance-prefix = ${lower(var.instance_name)}-${random_id.clusterid.hex}
node-tags = icp-cluster-${random_id.clusterid.hex}
multizone = true
EOF

}

data "template_file" "create_storage_class_sh" {
  template = "${file("${path.module}/../scripts/create_storageclass.sh")}"

  vars {
    master_node_url = "${google_compute_address.icp-master.address}"
    icp_password = "${local.icppassword}"
    icp_clustername = "${var.instance_name}-cluster.icp"
  }
}

data "template_file" "calico_hostlocal_ipam_sh" {
  template = "${file("${path.module}/../scripts/calico_hostlocal_ipam.sh")}"

  vars {
    icp_installer = "${local.icp-version}"
  }
}

##################################
### Deploy ICP to cluster
##################################
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy.git?ref=3.0.4"

    # Provide IP addresses for boot, master, mgmt, va, proxy and workers
    boot-node     = "${google_compute_instance.icp-boot.network_interface.0.network_ip}"
    bastion_host  = "${google_compute_instance.icp-boot.network_interface.0.access_config.0.nat_ip}"

    icp-host-groups = {
        master = ["${google_compute_instance.icp-master.*.network_interface.0.network_ip}"]
        proxy = "${slice(concat(google_compute_instance.icp-proxy.*.network_interface.0.network_ip,
                                google_compute_instance.icp-master.*.network_interface.0.network_ip),
                         var.proxy["nodes"] > 0 ? 0 : length(google_compute_instance.icp-proxy.*.network_interface.0.network_ip),
                         var.proxy["nodes"] > 0 ? length(google_compute_instance.icp-proxy.*.network_interface.0.network_ip) :
                                                  length(google_compute_instance.icp-proxy.*.network_interface.0.network_ip) +
                                                    length(google_compute_instance.icp-master.*.network_interface.0.network_ip))}"

        worker = ["${google_compute_instance.icp-worker.*.network_interface.0.network_ip}"]

        // make the master nodes managements nodes if we don't have any specified
        management = "${slice(concat(google_compute_instance.icp-mgmt.*.network_interface.0.network_ip,
                                     google_compute_instance.icp-master.*.network_interface.0.network_ip),
                              var.management["nodes"] > 0 ? 0 : length(google_compute_instance.icp-mgmt.*.network_interface.0.network_ip),
                              var.management["nodes"] > 0 ? length(google_compute_instance.icp-mgmt.*.network_interface.0.network_ip) :
                                                      length(google_compute_instance.icp-mgmt.*.network_interface.0.network_ip) +
                                                        length(google_compute_instance.icp-master.*.network_interface.0.network_ip))}"

        va = ["${google_compute_instance.icp-va.*.network_interface.0.network_ip}"]
    }

    # Provide desired ICP version to provision
    icp-inception = "${local.icp-version}"

    /* Workaround for terraform issue #10857
     When this is fixed, we can work this out automatically */
    cluster_size  = "${1 + var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"] + var.management["nodes"] + var.va["nodes"]}"

    ###################################################################################################################################
    ## You can feed in arbitrary configuration items in the icp_configuration map.
    ## Available configuration items availble from https://www.ibm.com/support/knowledgecenter/SSBS6K_3.1.0/installing/config_yaml.html
    icp_configuration = {
      "network_cidr"                    = "${var.pod_network_cidr}"
      "service_cluster_ip_range"        = "${var.service_network_cidr}"
      "cluster_lb_address"              = "${google_compute_address.icp-master.address}"
      "proxy_lb_address"                = "${google_compute_address.icp-proxy.address}"
      "cluster_CA_domain"               = "${var.cluster_cname != "" ? "${var.cluster_cname}" : "${var.instance_name}-cluster.icp"}"
      "cluster_name"                    = "${var.instance_name}-cluster.icp"

      "kubelet_nodename"                = "hostname"

      "calico_ip_autodetection_method"  = "first-found"
      "firewall_enabled"                = "${substr(var.image["family"], 0, 4) == "rhel" ? "true" : "false"}" # this is true by default in rhel but false in ubuntu

      # An admin password will be generated if not supplied in terraform.tfvars
      "default_admin_password"          = "${local.icppassword}"

      # This is the list of disabled management services
      "management_services"             = "${local.disabled_management_services}"

      "private_registry_enabled"        = "${var.registry_server != "" ? "true" : "false" }"
      "private_registry_server"         = "${local.registry_server}"
      "image_repo"                      = "${local.image_repo}" # Will either be our private repo or external repo
      "docker_username"                 = "${local.docker_username}" # Will either be username generated by us or supplied by user
      "docker_password"                 = "${local.docker_password}" # Will either be username generated by us or supplied by user

      "kube_apiserver_extra_args"           = ["--cloud-provider=gce", "--cloud-config=/etc/cfc/conf/gce.conf"]
      "kube_controller_manager_extra_args"  = ["--cloud-provider=gce", "--cloud-config=/etc/cfc/conf/gce.conf", "--allocate-node-cidrs=true"]
      "kubelet_extra_args"                  = ["--cloud-provider=gce"]

      # TODO: ICP 3.1.1+ use the routes created by the GCE cloud provider
      # and host-local IPAM, calico in policy-only mode
      # in ICP 3.1.0 and below, we reconfigure calico after installation
      "calico_networking_backend"  = "none"
      "calico_ipam_type"           = "host-local"
      "calico_ipam_subnet"         = "usePodCidr"
    }

    # We will let terraform generate a new ssh keypair
    # for boot master to communicate with worker and proxy nodes
    # during ICP deployment
    generate_key = true

    # SSH user and key for terraform to connect to newly created VMs
    # ssh_key is the private key corresponding to the public assumed to be included in the template
    ssh_user        = "icpdeploy"
    ssh_key_base64  = "${base64encode(tls_private_key.ssh.private_key_pem)}"
    ssh_agent       = false

    hooks = {
      # Make sure to wait for image load to complete
      # Make sure bootstrap is done on all nodes before proceeding
      "cluster-preconfig" = [
        "while [ ! -f /opt/ibm/.bootstrap_complete ]; do sleep 5; done"
      ]

      "cluster-postconfig" = ["echo No hook"]

      "preinstall" = ["echo No hook"]

      "boot-preconfig" = [
        "while [ ! -f /opt/ibm/.imageload_complete ]; do sleep 5; done"
      ]

      # create the storage classes
      "postinstall" = [
        "${data.template_file.create_storage_class_sh.rendered}",
        "${data.template_file.calico_hostlocal_ipam_sh.rendered}"
      ]
    }

    ## Alternative approach
    # hooks = {
    #   "cluster-preconfig" = ["echo No hook"]
    #   "cluster-postconfig" = ["echo No hook"]
    #   "preinstall" = ["echo No hook"]
    #   "postinstall" = ["echo No hook"]
    #   "boot-preconfig" = [
    #     # "${var.image_location == "" ? "exit 0" : "echo Getting archives"}",
    #     "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
    #     "sudo mv /tmp/load_image.sh /opt/ibm/scripts/",
    #     "sudo chmod a+x /opt/ibm/scripts/load_image.sh",
    #     "/opt/ibm/scripts/load_image.sh -p ${var.image_location} -r ${local.registry_server} -c ${local.docker_password}"
    #   ]
    # }

}

output "ICP Console load balancer IP (external)" {
  value = "${google_compute_address.icp-master.address}"
}

output "ICP Proxy load balancer IP (external)" {
  value = "${google_compute_address.icp-proxy.address}"
}

output "ICP Console URL" {
  value = "https://${google_compute_address.icp-master.address}:8443"
}

output "ICP Registry URL" {
  value = "${google_compute_address.icp-master.address}:8500"
}

output "ICP Kubernetes API URL" {
  value = "https://${google_compute_address.icp-master.address}:8001"
}

output "ICP Admin Username" {
  value = "admin"
}

output "ICP Admin Password" {
  value = "${local.icppassword}"
}
