resource "google_filestore_instance" "icp-registry" {
  provider = "google-beta"

  name = "${var.instance_name}-${random_id.clusterid.hex}-registry-fs"
  zone = "${element(local.zones, 0)}"
  tier = "PREMIUM"

  file_shares {
    capacity_gb = 2560
    name        = "icpregistry"
  }

  networks {
    network = "${google_compute_network.icp_vpc.name}"
    modes   = ["MODE_IPV4"]
  }
}
