############################
# Traffic Policy
############################

resource "aws_route53_traffic_policy" "policies" {
  for_each = var.traffic_policies

  name     = each.value.name
  comment  = each.value.comment
  document = jsonencode(each.value.document)
}
