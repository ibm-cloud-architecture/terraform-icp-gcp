resource "google_storage_bucket" "icp-binaries" {
  count = "${(substr(var.image_location, 0, 2) != "gs" && substr(var.docker_package_location, 0, 2) != "gs") ? 1 : 0}"
  name   = "icp-binaries-${random_id.clusterid.hex}"
  storage_class = "REGIONAL"
  location = "${var.region}"
}

resource "google_storage_bucket_object" "icp-install" {
  count   = "${var.image_location != "" && substr(var.image_location, 0, 2) != "gs" ? 1 : 0}"
  name    = "${basename(var.image_location)}"
  source  = "${path.module}/${var.image_location}"
  bucket  = "${element(
    compact(
      concat(google_storage_bucket.icp-binaries.*.name,
             list(var.existing_storage_bucket))), 0)}"
}

resource "google_storage_bucket_object" "docker-install" {
  count   = "${var.docker_package_location != "" && substr(var.docker_package_location, 0, 2) != "gs" ? 1 : 0}"
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
  location = "${var.region}"
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
