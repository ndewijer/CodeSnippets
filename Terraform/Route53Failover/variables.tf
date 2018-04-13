variable "domain" {}

variable "production_alb_name" {}

variable "production_alb_zone" {}

variable "failover_alb_name" {}

variable "failover_alb_zone" {}

variable "type" {
  default = "http"
}

variable "port" {
  default = 80
}

variable "resource_path" {
  default = "/"
}

variable "stringmatch" {}

variable "request_interval" {
  default = 30
}

variable "failure_threshold" {
  default = 5
}

variable "dns_zone" {
  default = ""
}
