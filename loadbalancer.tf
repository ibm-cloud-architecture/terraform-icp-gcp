resource "null_resource" "icp-healthcheck" {
  depends_on = [
    "google_compute_router_nat.icp-nat",
    "google_compute_http_health_check.master-health"
  ]

  count = "${var.master["nodes"]}"

  # copy and build the http healthcheck image
  connection {
    host          = "${element(google_compute_instance.icp-master.*.network_interface.0.network_ip, count.index)}"
    user          = "icpdeploy"
    private_key   = "${tls_private_key.ssh.private_key_pem}"
    bastion_host  = "${google_compute_instance.icp-boot.network_interface.0.access_config.0.nat_ip}"
  }

  provisioner "file" {
    content = <<EOF
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "name": "icp-http-healthcheck",
    "namespace": "kube-system",
    "annotations": {
        "scheduler.alpha.kubernetes.io/critical-pod": ""
    }
  },
  "spec":{
    "hostNetwork": true,
    "containers":[
      {
        "name": "icp-http-healthcheck",
        "image": "ibmcase/icp-http-healthcheck:latest",
        "imagePullPolicy": "IfNotPresent",
        "env": [
          {
            "name": "NODE_EXTRA_CA_CERTS",
            "value": "/etc/cfc/conf/ca.crt"
          }
        ],
        "volumeMounts": [
          {
            "mountPath": "/etc/cfc/conf",
            "name": "data"
          }
        ]
      }
    ],
    "volumes": [
      {
        "hostPath": {
          "path": "/etc/cfc/conf"
        },
        "name": "data"
      }
    ]
  }
}
EOF
    destination = "/tmp/icp-http-healthcheck.json"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/icp-http-healthcheck",
    ]
  }

  provisioner "file" {
    source = "${path.module}/healthcheck/"
    destination = "/tmp/icp-http-healthcheck"
  }

  provisioner "remote-exec" {
    inline = [
      "docker build -t ibmcase/icp-http-healthcheck:latest /tmp/icp-http-healthcheck"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/cfc/pods",
      "sudo chmod 700 /etc/cfc/pods",
      "sudo mv /tmp/icp-http-healthcheck.json /etc/cfc/pods"
    ]
  }
}

/* TODO: SSL health checks don't work with load balancers yet.  we added the above
workaround instead for now which is a http static pod that performs healthchecks
against the TLS apiserver port and lock it down

resource "google_compute_health_check" "master-8443" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-8443"
  check_interval_sec = 5
  timeout_sec        = 5

  ssl_health_check {
    port = 8443
  }
}

resource "google_compute_health_check" "master-9443" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-9443"
  check_interval_sec = 5
  timeout_sec        = 5

  ssl_health_check {
    port = 9443
  }
}

resource "google_compute_health_check" "master-8500" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-8500"
  check_interval_sec = 5
  timeout_sec        = 5

  ssl_health_check {
    port = 8500
  }
}

resource "google_compute_health_check" "master-8600" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-8600"
  check_interval_sec = 5
  timeout_sec        = 5

  ssl_health_check {
    port = 8600
  }
}

resource "google_compute_health_check" "master-8001" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-8001"
  check_interval_sec = 5
  timeout_sec        = 5

  ssl_health_check {
    port = 8001
  }
}
*/

resource "google_compute_http_health_check" "master-health" {
  depends_on = ["google_compute_firewall.master-health"]

  name               = "${var.instance_name}-${random_id.clusterid.hex}-master-health"
  check_interval_sec = 5
  timeout_sec        = 5
  port               = 3000
  request_path       = "/healthz"
}

resource "google_compute_http_health_check" "proxy-health" {
  name               = "${var.instance_name}-${random_id.clusterid.hex}-proxy-health"
  check_interval_sec = 5
  timeout_sec        = 5
  port               = 80
  request_path       = "/healthz"
}

resource "google_compute_address" "icp-master" {
  name = "${var.instance_name}-${random_id.clusterid.hex}-master-addr"
}

resource "google_compute_target_pool" "icp-master" {
  name = "${var.instance_name}-${random_id.clusterid.hex}-master"

  instances = [
    "${google_compute_instance.icp-master.*.self_link}"
  ]

  health_checks = [
    "${google_compute_http_health_check.master-health.name}"
  ]
}

resource "google_compute_forwarding_rule" "master-8001" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-master-8001"
  description = "forward ICP master traffic to 8001"
  target      = "${google_compute_target_pool.icp-master.self_link}"
  ip_address  = "${google_compute_address.icp-master.self_link}"
  ip_protocol = "TCP"
  port_range  = "8001-8001"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
}

resource "google_compute_forwarding_rule" "master-8443" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-master-8443"
  description = "forward ICP master traffic to 8443"

  target      = "${google_compute_target_pool.icp-master.self_link}"
  ip_address  = "${google_compute_address.icp-master.self_link}"
  ip_protocol = "TCP"
  port_range  = "8443-8443"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }

}

resource "google_compute_forwarding_rule" "master-9443" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-master-9443"
  description = "forward ICP master traffic to 9443"
  target      = "${google_compute_target_pool.icp-master.self_link}"
  ip_address  = "${google_compute_address.icp-master.self_link}"
  ip_protocol = "TCP"
  port_range  = "9443-9443"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
}

resource "google_compute_forwarding_rule" "master-8500" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-master-8500"
  description = "forward ICP master traffic to 8500"

  target      = "${google_compute_target_pool.icp-master.self_link}"
  ip_address  = "${google_compute_address.icp-master.self_link}"
  ip_protocol = "TCP"
  port_range  = "8500-8500"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
}

resource "google_compute_forwarding_rule" "master-8600" {
  name        = "${var.instance_name}-${random_id.clusterid.hex}-master-8600"
  description = "forward ICP master traffic to 8600"

  target      = "${google_compute_target_pool.icp-master.self_link}"
  ip_address  = "${google_compute_address.icp-master.self_link}"
  ip_protocol = "TCP"
  port_range  = "8600-8600"

  lifecycle {
    ignore_changes = [
      "ip_address"
    ]
  }
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
