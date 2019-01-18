resource "google_compute_http_health_check" "proxy-health" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-proxy-health"
  check_interval_sec = 5
  timeout_sec        = 5
  port               = 80
  request_path       = "/healthz"
}

resource "google_compute_address" "icp-proxy" {
  name = "${var.instance_name}-${random_id.clusterid.hex}-proxy-addr"
}

resource "google_compute_target_pool" "icp-proxy" {
  name = "${var.instance_name}-${random_id.clusterid.hex}-proxy"

  // add all masters if there aren't any proxy nodes
  instances = [
    "${slice(concat(google_compute_instance.icp-proxy.*.self_link,
                    google_compute_instance.icp-master.*.self_link),
      var.proxy["nodes"] > 0 ? 0 : length(google_compute_instance.icp-proxy.*.self_link),
      var.proxy["nodes"] > 0 ? length(google_compute_instance.icp-proxy.*.self_link) :
        length(google_compute_instance.icp-proxy.*.self_link) +
        length(google_compute_instance.icp-master.*.self_link))}"
  ]

  health_checks = [
    "${google_compute_http_health_check.proxy-health.name}"
  ]
}

resource "google_compute_forwarding_rule" "proxy-80" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-proxy-80"
  description = "forward ICP master traffic to 80"

  target      = "${google_compute_target_pool.icp-proxy.self_link}"
  ip_address  = "${google_compute_address.icp-proxy.self_link}"
  ip_protocol = "TCP"
  port_range  = "80-80"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
}


resource "google_compute_forwarding_rule" "proxy-443" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-proxy-443"
  description = "forward ICP master traffic to 443"

  target      = "${google_compute_target_pool.icp-proxy.self_link}"
  ip_address  = "${google_compute_address.icp-proxy.self_link}"
  ip_protocol = "TCP"
  port_range  = "443-443"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
}
