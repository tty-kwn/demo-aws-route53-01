############################
# Health Check
############################

resource "aws_route53_health_check" "checks" {
  for_each = var.health_checks

  type              = each.value.type
  fqdn              = each.value.fqdn
  port              = each.value.port
  resource_path     = each.value.resource_path
  request_interval  = each.value.request_interval
  failure_threshold = each.value.failure_threshold
  disabled          = !each.value.enabled

  tags = {
    Name = each.key
  }
}
