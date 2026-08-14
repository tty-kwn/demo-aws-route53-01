variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

############################
# Hosted Zone
############################

variable "zones" {
  description = "Route53 Hosted Zones managed by Terraform"

  type = map(object({
    name    = string
    type    = string
    comment = optional(string)

    vpc_ids = optional(list(string), [])
  }))

  default = {}
}

############################
# Health Check
############################

variable "health_checks" {
  description = "Route53 Health Checks managed by Terraform"

  type = map(object({
    type              = string
    fqdn              = string
    port              = number
    resource_path     = optional(string)
    request_interval  = optional(number, 30)
    failure_threshold = optional(number, 3)
    enabled           = optional(bool, true)
  }))

  default = {}
}

############################
# DNS Record
############################

variable "dns_records" {
  description = "Route53 DNS Records managed by Terraform"

  type = map(object({
    zone_key = string

    name    = string
    type    = string
    ttl     = optional(number)
    records = optional(list(string), [])

    health_check_key = optional(string)

    routing = optional(object({
      type           = string
      set_identifier = string

      weight        = optional(number)
      failover_role = optional(string)
    }))
  }))

  default = {}
}

############################
# Traffic Policy
############################

variable "traffic_policies" {
  description = "Route53 Traffic Policies managed by Terraform"

  type = map(object({
    name     = string
    comment  = optional(string)
    document = any
  }))

  default = {}
}
