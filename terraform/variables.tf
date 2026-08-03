variable "hcloud_token" {
  description = "Hetzner Cloud API token with Read & Write permissions"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Hetzner location. hel1 = Helsinki (closest to Estonia), fsn1 = Falkenstein, nbg1 = Nuremberg. CAX/ARM is available in all three."
  type        = string
  default     = "hel1"
}

variable "server_type" {
  description = "ARM (Ampere) server type. cax11 = 2 vCPU/4GB, cax21 = 4 vCPU/8GB, cax31 = 8 vCPU/16GB."
  type        = string
  default     = "cax21"
}

variable "image" {
  description = "OS image. Hetzner serves the arm64 build automatically for CAX servers."
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key_path" {
  description = "Path to your LOCAL public SSH key (the .pub). Private key stays on your machine."
  type        = string
  default     = "~/.ssh/id_ed25519_demo.pub"
}

variable "ssh_allowed_ips" {
  description = "CIDRs allowed to reach SSH (port 22). Lock this to your own IP if you can, e.g. [\"1.2.3.4/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
