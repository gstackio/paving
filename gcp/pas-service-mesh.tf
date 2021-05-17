
resource "google_dns_record_set" "wildcard-mesh" {
  name = "*.mesh.${var.environment_name}.${data.google_dns_managed_zone.hosted-zone.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = var.hosted_zone

  rrdatas = [google_compute_global_address.mesh-lb.address]
}



# HTTP/S
resource "google_compute_backend_service" "mesh-lb" {
  name        = "${var.environment_name}-mesh-lb"
  port_name   = "mesh"
  protocol    = "HTTP"
  timeout_sec = 900
  enable_cdn  = false

  dynamic "backend" {
    for_each = { for group in google_compute_instance_group.mesh-lb.* : group.self_link => group }
    iterator = instance_group
    content {
      group = instance_group.value.self_link
    }
  }

  health_checks = [google_compute_http_health_check.mesh-lb.self_link]
}

resource "google_compute_instance_group" "mesh-lb" {
  name = "${var.environment_name}-mesh-lb-${count.index}"
  zone = element(var.availability_zones, count.index)

  count = length(var.availability_zones)

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_global_address" "mesh-lb" {
  name = "${var.environment_name}-mesh-lb"
}

resource "google_compute_url_map" "mesh-https-lb" {
  name = "${var.environment_name}-mesh-https-lb"

  default_service = google_compute_backend_service.mesh-lb.self_link
}

resource "google_compute_target_http_proxy" "mesh-http-lb" {
  name    = "${var.environment_name}-mesh-http-lb"
  url_map = google_compute_url_map.mesh-https-lb.self_link
}

resource "google_compute_target_https_proxy" "mesh-https-lb" {
  name             = "${var.environment_name}-mesh-https-lb"
  url_map          = google_compute_url_map.mesh-https-lb.self_link
  ssl_certificates = [google_compute_ssl_certificate.certificate.self_link]
}

resource "google_compute_global_forwarding_rule" "mesh-http-lb-80" {
  name       = "${var.environment_name}-mesh-http-lb"
  ip_address = google_compute_global_address.mesh-lb.address
  target     = google_compute_target_http_proxy.mesh-http-lb.self_link
  port_range = "80"
}

resource "google_compute_global_forwarding_rule" "mesh-https-lb-443" {
  name       = "${var.environment_name}-mesh-https-lb"
  ip_address = google_compute_global_address.mesh-lb.address
  target     = google_compute_target_https_proxy.mesh-https-lb.self_link
  port_range = "443"
}

resource "google_compute_http_health_check" "mesh-lb" {
  name                = "${var.environment_name}-mesh-lb-health-check"
  port                = 8002
  request_path        = "/healthcheck"
  check_interval_sec  = 5
  timeout_sec         = 3
  healthy_threshold   = 6
  unhealthy_threshold = 3
}




resource "google_compute_firewall" "mesh-lb" {
  name    = "${var.environment_name}-mesh-lb-firewall"
  network = google_compute_network.network.self_link

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags = ["${var.environment_name}-mesh-lb"]
}

resource "google_compute_firewall" "mesh-lb-health-check" {
  name    = "${var.environment_name}-mesh-lb-health-check"
  network = google_compute_network.network.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8002"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  target_tags = ["${var.environment_name}-mesh-lb"]
}



locals {
  stable_config_mesh = {
    mesh_backend_service_name = google_compute_backend_service.mesh-lb.name

    mesh_dns_domain = replace(replace(google_dns_record_set.wildcard-mesh.name, "/\\.$/", ""), "*.", "")
  }
}

output "stable_config_mesh" {
  value = jsonencode(local.stable_config_mesh)
  sensitive = false
}
