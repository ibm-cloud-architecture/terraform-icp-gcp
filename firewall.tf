resource "google_compute_firewall" "boot-node-ssh" {
  count   = "${var.boot["nodes"] > 0 ? 1 : 0}"
  name    = "${var.instance_name}-${random_id.clusterid.hex}-boot-allow-ssh"
  network = "${google_compute_network.icp_vpc.self_link}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["icp-boot-${random_id.clusterid.hex}"]
}

resource "google_compute_firewall" "cluster-traffic" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-allow-cluster"
  network = "${google_compute_network.icp_vpc.self_link}"

  allow {
    protocol = "all"
  }

  priority = 800

  source_tags = [
    "icp-cluster-${random_id.clusterid.hex}"
  ]
  source_ranges = [
    "${google_compute_subnetwork.icp_region_subnet.ip_cidr_range}"
  ]
  target_tags = ["icp-cluster-${random_id.clusterid.hex}"]
}

resource "google_compute_firewall" "master" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-master-allow"
  network = "${google_compute_network.icp_vpc.self_link}"

  allow {
    protocol = "tcp"
    ports = [
      "8443", "9443", "8001", "8500", "8600"
    ]
  }

  source_ranges = [ "0.0.0.0/0" ]
  target_tags = [
    "icp-master-${random_id.clusterid.hex}"
  ]
}

resource "google_compute_firewall" "master-health" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-master-health"
  network = "${google_compute_network.icp_vpc.self_link}"

  allow {
    protocol = "tcp"
    ports = [
      "3000"
    ]
  }

  source_ranges = [
    "35.191.0.0/16" ,
    "130.211.0.0/22"
  ]

  target_tags = [
    "icp-master-${random_id.clusterid.hex}"
  ]
}

resource "google_compute_firewall" "proxy" {
  name    = "${var.instance_name}-${random_id.clusterid.hex}-proxy-allow"
  network = "${google_compute_network.icp_vpc.self_link}"

  allow {
    protocol = "tcp"
    ports = [
      "80", "443"
    ]
  }

  source_ranges = [ "0.0.0.0/0" ]
  target_tags = [
    "icp-proxy-${random_id.clusterid.hex}"
  ]
}
