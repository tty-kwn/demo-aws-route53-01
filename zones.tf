############################
# Hosted Zone
############################

resource "aws_route53_zone" "zones" {
  for_each = var.zones

  name    = each.value.name
  comment = each.value.comment

  dynamic "vpc" {
    for_each = each.value.vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = {
    Name = each.key
  }
}
