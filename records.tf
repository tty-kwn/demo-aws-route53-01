############################
# DNS Record
############################

resource "aws_route53_record" "records" {
  for_each = var.dns_records

  zone_id = aws_route53_zone.zones[each.value.zone_key].zone_id

  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.routing == null ? each.value.ttl : null
  records = each.value.routing == null ? each.value.records : null

  health_check_id = (
    each.value.health_check_key != null
    ? aws_route53_health_check.checks[each.value.health_check_key].id
    : null
  )

  dynamic "weighted_routing_policy" {
    for_each = (
      each.value.routing != null && each.value.routing.type == "WEIGHTED"
      ? [each.value.routing]
      : []
    )
    content {
      weight = weighted_routing_policy.value.weight
    }
  }

  dynamic "failover_routing_policy" {
    for_each = (
      each.value.routing != null && each.value.routing.type == "FAILOVER"
      ? [each.value.routing]
      : []
    )
    content {
      type = weighted_routing_policy.value.failover_role
    }
  }

  set_identifier = each.value.routing != null ? each.value.routing.set_identifier : null

  dynamic "alias" {
    for_each = []
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = alias.value.evaluate_target_health
    }
  }
}
