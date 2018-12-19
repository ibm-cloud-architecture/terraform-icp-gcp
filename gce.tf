provider "google" {
  # set GOOGLE_CREDENTIALS in the environment to point at the json key
  # you can also set  GOOGLE_PROJECT, and GOOGLE_REGION
  region = "${var.region}"
  project = "${var.project}"
}

provider "google-beta" {
  # set GOOGLE_CREDENTIALS in the environment to point at the json key
  # you can also set  GOOGLE_PROJECT, and GOOGLE_REGION
  region = "${var.region}"
  project = "${var.project}"
}

data "google_project" "icp_project" {}
data "google_compute_regions" "available" {}
data "google_compute_zones" "available" {}

locals {
  zones         = "${formatlist("%s-%s", var.region, var.zones)}"

  icppassword   = "${var.icppassword != "" ? "${var.icppassword}" : "${random_id.adminpassword.hex}"}"

  docker_package_uri = "${var.docker_package_location != "" ? "${var.docker_package_location}" : "" }"

  #######
  ## Intermediate interpolations for the private registry
  ## Whether we are provided with details of an external, or we create one ourselves
  ## the image_repo and docker_username / docker_password will always be available and consistent
  #######

  # If we stand up a image registry what will the registry_server name and namespace be
  registry_server = "${var.registry_server != "" ? "${var.registry_server}" : "" }"
  namespace       = "${dirname(var.icp_inception_image)}" # This will typically return ibmcom

  # The final image repo will be either interpolated from what supplied in icp_inception_image or
  image_repo      = "${var.registry_server == "" ? "" : "${local.registry_server}/${local.namespace}"}"
  icp-version     = "${format("%s%s%s", "${local.docker_username != "" ? "${local.docker_username}:${local.docker_password}@" : ""}",
                      "${var.registry_server != "" ? "${var.registry_server}/" : ""}",
                      "${var.icp_inception_image}")}"

  # If we're using external registry we need to be supplied registry_username and registry_password
  docker_username = "${var.registry_username != "" ? var.registry_username : ""}"
  docker_password = "${var.registry_password != "" ? var.registry_password : ""}"

  # This is just to have a long list of disabled items to use in icp-deploy.tf
  disabled_list = "${list("disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled","disabled")}"

  disabled_management_services = "${zipmap(var.disabled_management_services, slice(local.disabled_list, 0, length(var.disabled_management_services)))}"
}

# Generate a new key if this is required for deployment
resource "random_id" "clusterid" {
  byte_length = "2"
}

# Generate a random string in case user wants us to generate admin password
resource "random_id" "adminpassword" {
  byte_length = "16"
}
