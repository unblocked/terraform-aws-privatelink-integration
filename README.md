# Terraform AWS PrivateLink integration

Offers a PostgreSQL database in your VPC to Unblocked through an AWS PrivateLink endpoint
service. Unblocked reaches only the targets you register, through an endpoint you approve.
There is no peering, no internet exposure and no route into your VPC.

This module is the Terraform form of the console and CLI steps in Unblocked's PrivateLink
setup guide.

## What it creates

- An internal **Network Load Balancer** in the subnets you choose, listening on the database
  port, with cross-zone load balancing on.
- A **TCP target group** of IP targets, with a TCP health check every 10 seconds and a
  30-second deregistration delay.
- A **security group** on the NLB. It has no inbound rules and is not applied to PrivateLink
  traffic, so the NLB only takes connections through the endpoint service. Outbound, it
  reaches only the database port.
- With `database_security_group_id` set, an **inbound rule** on your database's security
  group admitting the NLB on the port.
- A **VPC endpoint service** on the NLB, with no private DNS name. By default you accept each
  connection; set `auto_accept_connections = true` to accept connections from the allowed
  principals automatically.
- An **allowed principal** entry for Unblocked's endpoint-manager role.

The target group starts empty. You register the database IPs in it and keep them current
outside Terraform, because they change after failovers and AWS maintenance. The target group
does not track its targets in Terraform state, so these changes cause no drift. See
[Keeping the target IPs current](#keeping-the-target-ips-current).

## Usage

Pin the module to a release tag when consuming it from GitHub:

```hcl
module "unblocked_privatelink" {
  source = "git::https://github.com/unblocked/terraform-aws-privatelink-integration.git?ref=v0.1.0"

  name                       = "unblocked-privatelink"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb"]
  database_security_group_id = "sg-0123456789abcdef0"
}
```

Then register the database IPs, as described in [Finding the target IPs](#finding-the-target-ips):

```bash
aws elbv2 register-targets \
  --target-group-arn "$(terraform output -raw target_group_arn)" \
  --targets Id=10.0.1.25,Port=5432 Id=10.0.2.31,Port=5432
```

If your database's security group is managed with inline `ingress` blocks on an
`aws_security_group` resource, leave `database_security_group_id` unset: Terraform would
remove the module's rule on the next apply of that resource. Instead, allow
`nlb_security_group_id` on the port in your own configuration. The NLB can then reach the VPC
CIDR on the port, or the CIDRs in `target_cidr_blocks`.

## Inputs

| Name | Default | Description |
|------|---------|-------------|
| `name` | | Name prefix for every resource, 2–32 characters. |
| `vpc_id` | | VPC of the database. |
| `subnet_ids` | | Private subnets for the NLB, one per AZ. The service is offered in exactly these AZs. |
| `port` | `5432` | Database port, also exposed by the NLB. |
| `database_security_group_id` | `null` | Your database's security group. The NLB may reach only it, and the module adds the inbound rule. |
| `target_cidr_blocks` | VPC CIDR | Where the NLB may send traffic when `database_security_group_id` is unset. |
| `allowed_principals` | Unblocked's role | IAM role ARNs allowed to create endpoints. |
| `unblocked_region` | `us-west-2` | Region Unblocked connects from. Added to the service's supported regions. |
| `auto_accept_connections` | `false` | Accept connections from allowed principals automatically. Leave off to approve each one. |
| `tags` | `{}` | Tags for every resource. |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint_service_name` | Give this to Unblocked. |
| `owner_account_id` | Give this to Unblocked. |
| `port` | Give this to Unblocked. |
| `endpoint_service_id` | For accepting or rejecting connections. |
| `nlb_security_group_id` | The NLB's security group. |
| `target_group_arn` | Register and maintain the database IPs in this target group. |
| `nlb_arn` | For operations. |

Requires Terraform 1.5 or later and AWS provider 6.0 or later.

## Finding the target IPs

An NLB forwards to IP addresses, not to RDS endpoints. Resolve each instance's endpoint; the
endpoint of a private instance resolves to its private IP from anywhere:

```bash
aws rds describe-db-instances --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].Endpoint.Address' --output text
dig +short <instance endpoint address>
```

Register the reader instances if Unblocked should only read from replicas.

## Keeping the target IPs current

The NLB sends traffic to fixed IP addresses, but the IP address behind an Aurora instance is
not fixed. **You own the target group, and you must update it whenever these IPs change.**
Unblocked cannot see or change it. IPs change when:

- **Failover:** the writer fails over, a reader is promoted to writer, and the old writer comes
  back as a reader. A target group of reader IPs then points at the new writer and misses the
  new reader.
- **AWS maintenance:** OS or engine patching, or recovery from a hardware failure, can move an
  instance to a new host with a new IP.
- **Your own changes:** changing an instance class, or adding or removing readers.

When a registered IP goes stale, its health check fails and the NLB stops sending traffic to
it. Once no target is healthy, Unblocked cannot connect. Check the target group after each of
these events, or automate the update, for example with an EventBridge rule on RDS events that
runs a Lambda function to resolve the instance endpoints again and update the target group.
AWS describes this pattern, with a sample CloudFormation template, in
[Access Amazon RDS across VPCs using AWS PrivateLink and Network Load Balancer](https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/).
The sample tracks only the writer's IP, so extend it if you register readers.

Do not manage the targets with `aws_lb_target_group_attachment` resources. Terraform would
re-register stale IPs after a failover and remove targets your automation added.

## Connecting Unblocked

1. **Apply the module and register the targets.**
2. **Give Unblocked** the endpoint service name, your AWS account ID, the region, the port and
   the database hostname. Unblocked verifies the database's TLS certificate against that
   hostname, so give the RDS endpoint name (for Aurora, the cluster reader endpoint), not an
   IP address or a custom DNS name.
3. **Accept the connection**, unless `auto_accept_connections` is on. Unblocked's endpoint
   waits in `pendingAcceptance`. Check that it comes from Unblocked's account
   (`029574882031`), then accept it:

   ```bash
   aws ec2 describe-vpc-endpoint-connections \
     --filters Name=service-id,Values=<endpoint_service_id>
   aws ec2 accept-vpc-endpoint-connections \
     --service-id <endpoint_service_id> --vpc-endpoint-ids <vpce-id>
   ```

To cut Unblocked off, run `reject-vpc-endpoint-connections` on the same endpoint. Removing the
principal only stops new endpoints, not an accepted one.

## Regions and Availability Zones

Unblocked connects from `us-west-2`.

- **Same region:** Unblocked's endpoint uses the AZs your service offers, matched by AZ ID
  (for example `usw2-az1`). Put the NLB in at least two AZs.
- **Another region:** the module adds `us-west-2` to the service's supported regions. AWS
  bills inter-region data transfer to the sending side. Cross-region PrivateLink is not
  available in every AZ (for example `use1-az3`), so keep the NLB out of those.
