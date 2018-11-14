resource "google_storage_bucket" "icp-binaries" {
  count = "${var.existing_storage_bucket == "" ? 1 : 0}"
  name   = "icp-binaries-${random_id.clusterid.hex}"
  storage_class = "REGIONAL"
}

resource "google_storage_bucket_object" "icp-install" {
  count   = "${var.image_location != "" ? 1 : 0}"
  name    = "${basename(var.image_location)}"
  source  = "${path.module}/${var.image_location}"
  bucket  = "${element(
    compact(
      concat(google_storage_bucket.icp-binaries.*.name,
             list(var.existing_storage_bucket))), 0)}"
}

resource "google_storage_bucket_object" "docker-install" {
  count   = "${var.docker_package_location != "" ? 1 : 0}"
  name    = "${basename(var.docker_package_location)}"
  source  = "${path.module}/${var.docker_package_location}"

  bucket  = "${element(
    compact(
      concat(google_storage_bucket.icp-binaries.*.name,
             list(var.existing_storage_bucket))), 0)}"

}

resource "google_storage_bucket" "icp-config" {
  name   = "icp-config-${random_id.clusterid.hex}"
  storage_class = "REGIONAL"
}

/*
TODO
resource "google_storage_bucket_object" "icp-router-crt" {
  name    = "cfc-certs/icp-router.crt"
  bucket  = "${google_storage_bucket.icp-config.name}"
  source  = "${path.module}/cfc-certs/icp-router.crt"
}

resource "google_storage_bucket_object" "icp-router-key" {
  name    = "cfc-certs/icp-router.key"
  bucket  = "${google_storage_bucket.icp-config.name}"
  source  = "${path.module}/cfc-certs/icp-router.key"
}
*/

resource "google_storage_bucket_object" "cloud_provider_conf" {
  name    = "misc/cloudprovider/cloud_provider_gce.conf"
  bucket  = "${google_storage_bucket.icp-config.name}"
  content = <<EOF
[global]
project-id = ${var.project}
network-project-id = ${var.project}
network-name = ${google_compute_network.icp_vpc.name}
subnetwork-name = ${google_compute_subnetwork.icp_region_subnet.name}
node-instance-prefix = ${var.instance_name}-${random_id.clusterid.hex}
node-tags = icp-cluster-${random_id.clusterid.hex}
regional = true
multizone = true
EOF

}
