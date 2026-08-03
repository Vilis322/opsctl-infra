# ---------------------------------------------------------------------------
# SSH key — uploads your local public key so the server trusts it on boot
# ---------------------------------------------------------------------------
resource "hcloud_ssh_key" "default" {
  name       = "opsctl-key"
  public_key = file(var.ssh_public_key_path)
}

# ---------------------------------------------------------------------------
# Firewall — SSH (locked via var), plus HTTP/HTTPS for the demo ingress
# ---------------------------------------------------------------------------
resource "hcloud_firewall" "default" {
  name = "opsctl-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ping — handy for debugging, optional
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ---------------------------------------------------------------------------
# Private network — tidy foundation if you later add more nodes / k3s agents
# ---------------------------------------------------------------------------
resource "hcloud_network" "default" {
  name     = "opsctl-net"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "default" {
  network_id   = hcloud_network.default.id
  type         = "cloud"
  network_zone = "eu-central" # hel1 / fsn1 / nbg1 all live here
  ip_range     = "10.0.1.0/24"
}

# ---------------------------------------------------------------------------
# Server — the CAX21 (ARM) box your demos will run on
# ---------------------------------------------------------------------------
resource "hcloud_server" "demo" {
  name        = "opsctl-demo"
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.default.id]

  public_net {
    ipv4_enabled = true # ~€0.60/mo; set false for IPv6-only to save it
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.default.id
    ip         = "10.0.1.10"
  }

  labels = {
    project = "opsctl"
    env     = "demo"
  }

  # --- Hook point for the next layer ---
  # Point this at a cloud-init file to bootstrap k3s on first boot,
  # or leave it out and run Ansible against the output IP instead.
  # user_data = file("${path.module}/cloud-init.yaml")

  depends_on = [hcloud_network_subnet.default]
}
