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
}

resource "google_compute_router" "icp_router" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-router"
  network = "${google_compute_network.icp_vpc.name}"
}

resource "google_compute_router_nat" "icp-nat" {
  name                               = "${var.instance_name}-nat-${random_id.clusterid.hex}"
  router                             = "${google_compute_router.icp_router.name}"
  region                             = "${var.region}"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name = "${google_compute_subnetwork.icp_region_subnet.self_link}"
  }
}
