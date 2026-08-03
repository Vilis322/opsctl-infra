output "server_ipv4" {
  description = "Public IPv4 — use this for SSH / Ansible inventory"
  value       = hcloud_server.demo.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6"
  value       = hcloud_server.demo.ipv6_address
}

output "server_private_ip" {
  description = "Private network IP"
  value       = "10.0.1.10"
}

output "server_status" {
  value = hcloud_server.demo.status
}
