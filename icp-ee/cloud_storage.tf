/*
resource "google_storage_bucket" "icp-config" {
  name   = "icp-config-${random_id.clusterid.hex}"
  storage_class = "REGIONAL"
  location = "${var.region}"
}

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
