variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_name" {
  type    = string
  default = "mpay-demo-1"
}

variable "server_type" {
  type    = string
  default = "cpx11"
}

variable "server_location" {
  type    = string
  default = "hel1"
}

variable "image" {
  type    = string
  default = "ubuntu-22.04"
}

variable "ssh_public_key_path" {
  type = string
}

