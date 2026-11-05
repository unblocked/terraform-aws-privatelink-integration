# Terraform AWS PrivateLink integration

This module offers a database or other TCP service in your VPC to Unblocked through an AWS PrivateLink endpoint service. Unblocked reaches only the targets you register, through an endpoint created by the IAM role you allow. There is no peering, no internet exposure and no route into your VPC.

## Requirements

| Name | Version |
| --- | --- |
| Terraform | `>= 1.5.0` |
| AWS provider | `>= 6.0.0` |

The identity applying this module must be allowed to describe the VPC, manage security groups and their rules, create Network Load Balancers, target groups and listeners, manage VPC endpoint services and their permissions, and create an IAM role with an inline policy.

## Providers

| Name | Source | Version |
| --- | --- | --- |
| `aws` | `hashicorp/aws` | `>= 6.0.0` |

The module inherits the caller's AWS provider configuration. It does not configure credentials or a provider alias. Resources are created in the provider's region.

## Usage

Pin the module to a release tag when consuming it from GitHub:

```hcl
module "unblocked_privatelink" {
  source = "git::https://github.com/unblocked/terraform-aws-privatelink-integration.git?ref=v0.1.0"

  name                       = "unblocked-privatelink"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  database_security_group_id = "sg-0123456789abcdef0"

  allowed_principals = [
    "arn:aws:iam::UNBLOCKED_AWS_ACCOUNT_ID:role/UNBLOCKED_ENDPOINT_MANAGER_ROLE_NAME",
  ]
  verification_external_id = "UNBLOCKED_PRIVATELINK_EXTERNAL_ID"
  verification_role_name   = "orders-db"
}
```

`allowed_principals`, `verification_external_id` and `verification_role_name` have no defaults, so the Unblocked identity you trust, your external ID and the role Unblocked assumes all stay visible in your Terraform configuration. Unblocked gives you the role ARN and shows your organization's external ID on its PrivateLink setup page. You choose the verification role's name: the module prefixes it with `UnblockedPrivateLink-`, so `orders-db` creates `UnblockedPrivateLink-orders-db`. A name that already starts with `UnblockedPrivateLink` is used as is.

Then register the target IPs, as described in [Finding the target IPs](#finding-the-target-ips):

```bash
aws elbv2 register-targets \
  --target-group-arn "$(terraform output -raw unblocked_target_group_arn)" \
  --targets Id=10.0.1.25,Port=5432 Id=10.0.2.31,Port=5432
```

If your database's security group is managed with inline `ingress` blocks on an `aws_security_group` resource, leave `database_security_group_id` unset: Terraform would remove the module's rule on the next apply of that resource. Instead, allow `nlb_security_group_id` on the port in your own configuration. The NLB can then reach the VPC CIDR on the port, or the CIDRs in `target_cidr_blocks`.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `name` | Name prefix for every resource, 2–32 characters of letters, digits and hyphens. The NLB and target group take it as their name. | `string` | n/a | yes |
| `vpc_id` | VPC of the database. | `string` | n/a | yes |
| `subnet_ids` | Private subnets for the NLB, one per Availability Zone. The endpoint service is offered in exactly these AZs. | `list(string)` | n/a | yes |
| `allowed_principals` | Non-empty list of IAM role ARNs allowed to create endpoints to the service: the endpoint-manager role Unblocked gives you. | `list(string)` | n/a | yes |
| `verification_external_id` | External ID shown on Unblocked's PrivateLink setup page: `unblocked_privatelink_` and 32 hexadecimal characters. The verification role requires it. | `string` | n/a | yes |
| `verification_role_name` | Name of the role Unblocked assumes to verify that you own the endpoint service. Prefixed with `UnblockedPrivateLink-` unless it already starts with `UnblockedPrivateLink`; the full name must be at most 64 characters of letters, digits and `+=,.@_-`. Use a different name for each instance of the module in an account. | `string` | n/a | yes |
| `port` | Port the database listens on, and the port the NLB exposes. | `number` | `5432` | no |
| `database_security_group_id` | Security group of the database. When set, the NLB may reach only this group on the port, and the module adds an inbound rule to it admitting the NLB. | `string` | `null` | no |
| `target_cidr_blocks` | CIDR blocks the NLB may reach on the port when `database_security_group_id` is unset. Empty means the VPC's primary CIDR block. | `list(string)` | `[]` | no |
| `unblocked_region` | Region Unblocked connects from. Added to the service's supported regions when it differs from the provider's region. | `string` | `"us-west-2"` | no |
| `auto_accept_connections` | Accept endpoint connections from the allowed principals automatically. When `false`, you accept each connection before traffic flows. | `bool` | `false` | no |
| `tags` | Tags for every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| `endpoint_service_name` | Endpoint service name to provide to Unblocked. |
| `owner_account_id` | AWS account ID that owns the endpoint service, to provide to Unblocked. |
| `port` | Port the endpoint service exposes, to provide to Unblocked. |
| `endpoint_service_id` | Endpoint service ID, for accepting or rejecting connections. |
| `target_group_arn` | Target group to register and maintain the target IPs in. |
| `nlb_security_group_id` | Security group of the NLB. |
| `nlb_arn` | ARN of the NLB behind the endpoint service. |
| `verification_role_arn` | Verification role ARN, to provide to Unblocked. |

## Integration output

Terraform does not automatically promote a child module's outputs to the root module. Re-export the values Unblocked needs, and the target group for registering targets, from your configuration:

```hcl
output "unblocked_endpoint_service_name" {
  value       = module.unblocked_privatelink.endpoint_service_name
  description = "Endpoint service name to provide to Unblocked."
}

output "unblocked_owner_account_id" {
  value       = module.unblocked_privatelink.owner_account_id
  description = "AWS account ID to provide to Unblocked."
}

output "unblocked_port" {
  value       = module.unblocked_privatelink.port
  description = "Port to provide to Unblocked."
}

output "unblocked_verification_role_arn" {
  value       = module.unblocked_privatelink.verification_role_arn
  description = "Verification role ARN to provide to Unblocked."
}

output "unblocked_target_group_arn" {
  value       = module.unblocked_privatelink.target_group_arn
  description = "Target group to register the target IPs in."
}
```

After applying, retrieve them with:

```shell
terraform output -raw unblocked_endpoint_service_name
terraform output -raw unblocked_owner_account_id
terraform output -raw unblocked_port
terraform output -raw unblocked_verification_role_arn
```

## Resources created

Depending on the inputs, the module creates:

- An internal Network Load Balancer in `subnet_ids`, listening on `port`, with cross-zone load balancing on.
- A TCP target group of IP targets, with a TCP health check every 10 seconds and a 30-second deregistration delay. It starts empty.
- A TCP listener forwarding `port` to the target group.
- A security group on the NLB, with one outbound rule on `port`: to `database_security_group_id` when set, otherwise to each of `target_cidr_blocks` or the VPC CIDR.
- When `database_security_group_id` is set, an inbound rule on that group admitting the NLB on `port`.
- A VPC endpoint service on the NLB, with no private DNS name, supported in the provider's region and `unblocked_region`.
- One allowed-principal entry per role in `allowed_principals`.
- A verification role named after `verification_role_name`, with the `UnblockedPrivateLink-` prefix, that only the roles in `allowed_principals` can assume, and only with `verification_external_id`. Its inline policy allows `ec2:DescribeVpcEndpointServicePermissions` on this endpoint service and `iam:GetRole` on itself, nothing else.

## Security model

- The NLB's security group has no inbound rules, and its rules are not evaluated for PrivateLink traffic, so the NLB only takes connections through the endpoint service.
- Every Unblocked customer allows the same Unblocked role, so before creating an endpoint Unblocked assumes the verification role with your organization's external ID. It checks that the role requires exactly that ID and that it can read the endpoint service's allowed principals, which only the service's owner can do. The role's EC2 permission names this one endpoint service, so Unblocked cannot see any other endpoint service in your account. Another Unblocked organization cannot pass this check, so it cannot connect to your service even if it knows the service name.
- Only the roles in `allowed_principals` can create an endpoint to the service. With `auto_accept_connections = false`, each endpoint also needs your acceptance before traffic flows.
- Outbound, the NLB reaches only `port`, on the database's security group or the configured CIDRs.
- Unblocked reaches only the targets you register. There is no VPC peering, no route into your VPC and no internet exposure.
- To cut Unblocked off, reject its endpoint connection. Removing a principal only stops new endpoints, not an accepted one.

## Finding the target IPs

An NLB forwards to IP addresses, not to hostnames. For Amazon RDS and Aurora, resolve each instance's endpoint; the endpoint of a private instance resolves to its private IP from anywhere:

```bash
aws rds describe-db-instances --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].Endpoint.Address' --output text
dig +short <instance endpoint address>
```

Register the reader instances if Unblocked should only read from replicas.

## Keeping the target IPs current

The NLB sends traffic to fixed IP addresses, but the IP address behind an RDS or Aurora instance is not fixed. **You own the target group, and you must update it whenever these IPs change.** Unblocked cannot see or change it. IPs change when:

- **Failover:** the writer fails over, a reader is promoted to writer, and the old writer comes back as a reader. A target group of reader IPs then points at the new writer and misses the new reader.
- **AWS maintenance:** OS or engine patching, or recovery from a hardware failure, can move an instance to a new host with a new IP.
- **Your own changes:** changing an instance class, or adding or removing readers.

When a registered IP goes stale, its health check fails and the NLB stops sending traffic to it. Once no target is healthy, Unblocked cannot connect. Check the target group after each of these events, or automate the update, for example with an EventBridge rule on RDS events that runs a Lambda function to resolve the instance endpoints again and update the target group. AWS describes this pattern, with a sample CloudFormation template, in [Access Amazon RDS across VPCs using AWS PrivateLink and Network Load Balancer](https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/). The sample tracks only the writer's IP, so extend it if you register readers.

The target group does not track its targets in Terraform state, so these changes cause no drift. Do not manage the targets with `aws_lb_target_group_attachment` resources: Terraform would re-register stale IPs after a failover and remove targets your automation added.

## Connecting Unblocked

1. **Get your external ID.** Start the Aurora PostgreSQL PrivateLink setup in Unblocked and copy the external ID it shows into `verification_external_id`.
2. **Apply the module and register the targets.**
3. **Give Unblocked** the endpoint service name, your AWS account ID, the verification role ARN, the region, the port and the database hostname. Unblocked verifies the database's TLS certificate against that hostname, so give the RDS endpoint name (for Aurora, the cluster reader endpoint), not an IP address or a custom DNS name.
4. **Accept the connection**, unless `auto_accept_connections` is on. Unblocked's endpoint waits in `pendingAcceptance`. Check that its owner is the account in your `allowed_principals` role ARN (`UNBLOCKED_AWS_ACCOUNT_ID`), then accept it:

   ```bash
   aws ec2 describe-vpc-endpoint-connections \
     --filters Name=service-id,Values=<endpoint_service_id>
   aws ec2 accept-vpc-endpoint-connections \
     --service-id <endpoint_service_id> --vpc-endpoint-ids <vpce-id>
   ```

## Regions and Availability Zones

Unblocked connects from `unblocked_region`, `us-west-2` by default.

- **Same region:** Unblocked's endpoint uses the AZs your service offers, matched by AZ ID (for example `usw2-az1`). Put the NLB in at least two AZs.
- **Another region:** the module adds `unblocked_region` to the service's supported regions. AWS bills inter-region data transfer to the sending side. Cross-region PrivateLink is not available in every AZ (for example `use1-az3`), so keep the NLB out of those.
