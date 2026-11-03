data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

locals {
  use_database_security_group = var.database_security_group_id != null
  target_cidr_blocks          = local.use_database_security_group ? [] : (length(var.target_cidr_blocks) > 0 ? var.target_cidr_blocks : [data.aws_vpc.this.cidr_block])
}

resource "aws_security_group" "nlb" {
  name        = "${var.name}-nlb"
  description = "PrivateLink NLB of ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_targets" {
  for_each = toset(local.target_cidr_blocks)

  security_group_id = aws_security_group.nlb.id
  description       = "To the database"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_database" {
  count = local.use_database_security_group ? 1 : 0

  security_group_id            = aws_security_group.nlb.id
  description                  = "To the database"
  referenced_security_group_id = var.database_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "database_from_nlb" {
  count = local.use_database_security_group ? 1 : 0

  security_group_id            = var.database_security_group_id
  description                  = "From the Unblocked PrivateLink NLB"
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port

  tags = var.tags
}

resource "aws_lb" "this" {
  name                                                         = var.name
  internal                                                     = true
  load_balancer_type                                           = "network"
  subnets                                                      = var.subnet_ids
  security_groups                                              = [aws_security_group.nlb.id]
  enable_cross_zone_load_balancing                             = true
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = var.name
  port                 = var.port
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = !var.auto_accept_connections
  network_load_balancer_arns = [aws_lb.this.arn]
  supported_regions          = distinct([data.aws_region.current.region, var.unblocked_region])

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_vpc_endpoint_service_allowed_principal" "this" {
  for_each = toset(var.allowed_principals)

  vpc_endpoint_service_id = aws_vpc_endpoint_service.this.id
  principal_arn           = each.value
}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "verification_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.allowed_principals
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.verification_external_id]
    }
  }
}

data "aws_iam_policy_document" "verification" {
  statement {
    sid       = "DescribeEndpointServices"
    actions   = ["ec2:DescribeVpcEndpointServiceConfigurations"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadOwnTrustPolicy"
    actions   = ["iam:GetRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.verification_role_name}"]
  }
}

resource "aws_iam_role" "verification" {
  name                 = var.verification_role_name
  description          = "Lets Unblocked verify that this account owns the ${var.name} endpoint service"
  assume_role_policy   = data.aws_iam_policy_document.verification_assume.json
  max_session_duration = 3600

  tags = var.tags
}

resource "aws_iam_role_policy" "verification" {
  name   = "verify-endpoint-service"
  role   = aws_iam_role.verification.id
  policy = data.aws_iam_policy_document.verification.json
}
