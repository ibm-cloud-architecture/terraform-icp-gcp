//data "google_compute_zones" "available" {}

resource "google_compute_network" "icp_vpc" {
  name                    = "${var.instance_name}-${random_id.clusterid.hex}-vpc"
  auto_create_subnetworks = "false"
  description             = "ICP ${random_id.clusterid.hex} VPC"
}

resource "google_compute_subnetwork" "icp_region_subnet" {
  name          = "${var.instance_name}-${random_id.clusterid.hex}-subnet"

  ip_cidr_range = "${var.subnet_cidr}"

  private_ip_google_access = true

  region        = "${var.region}"
  network       = "${google_compute_network.icp_vpc.self_link}"

  secondary_ip_range {
   range_name    = "podnet"
   ip_cidr_range = "${var.pod_network_cidr}"
  }
}

/*
resource "google_compute_router" "icp_router" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-router"
  network = "${google_compute_network.icp_vpc.name}"

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_peer" "icp_router" {
  # join my BGP mesh
  count = "${var.master["nodes"] +
              var.proxy["nodes"] +
              var.management["nodes"] +
              var.va["nodes"] +
              var.worker["nodes"]}"

  name = "${format("${var.instance_name}-${random_id.clusterid.hex}-router-peer-%d", count.index)}"
  router = "${google_compute_router.icp_router.name}"

  interface = "${format("interface-%d", count.index)}"
  peer_ip_address = "${element(concat(
    google_compute_instance.icp-master.*.network_interface.0.network_ip,
    google_compute_instance.icp-proxy.*.network_interface.0.network_ip,
    google_compute_instance.icp-mgmt.*.network_interface.0.network_ip,
    google_compute_instance.icp-va.*.network_interface.0.network_ip,
    google_compute_instance.icp-worker.*.network_interface.0.network_ip), count.index)}"

  peer_asn = 64512
}
*/

module "nat" {
  source          = "GoogleCloudPlatform/nat-gateway/google"
  name            = "${var.instance_name}-${random_id.clusterid.hex}-nat-"
  region          = "${var.region}"
  zone            = "${element(local.zones, 0)}"
  network         = "${google_compute_network.icp_vpc.name}"
  subnetwork      = "${google_compute_subnetwork.icp_region_subnet.name}"
}
