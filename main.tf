# Require Terraform version greater than 0.12
terraform {
  required_version = ">= 0.12"
}

# Create Consul Encryption Key
resource "random_id" "encrypt_key" {
  byte_length = 16
  lifecycle {
    create_before_destroy = true
  }
}

# Create Consul CA Certificate
resource "tls_private_key" "private_key" {
  algorithm = "ECDSA"
  lifecycle {
    create_before_destroy = true
  }
}

resource "random_integer" "serial_number" {
  min     = 1000000000
  max     = 9999999999
  lifecycle {
    create_before_destroy = true
  }
}

resource "tls_self_signed_cert" "example" {
  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.private_key.private_key_pem
  is_ca_certificate = true
  validity_period_hours = 43800

  subject {
    common_name = "Consul Agent CA ${random_integer.serial_number.result}${random_integer.serial_number.result}"
    country     = "US"
    postal_code = "94105"
    province    = "CA"
    locality    = "San Francisco"
    street_address = ["101 Second Street"]
    organization = "HashiCorp Inc." 
  }
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# AWS Secret Manager to pass encrypt key and private key
resource "aws_secretsmanager_secret" "secrets" {
  name                = "${var.cluster_name}-secrets"
}

resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id     = "${aws_secretsmanager_secret.secrets.id}"
  secret_string = jsonencode({encrypt_key = random_id.encrypt_key.b64_std, private_key = tls_private_key.private_key.private_key_pem })
}


# Create Consul ASG
resource "aws_autoscaling_group" "autoscaling_group" {
  name_prefix = var.cluster_name

  launch_configuration = aws_launch_configuration.launch_configuration.name

  availability_zones  = var.availability_zones
  vpc_zone_identifier = var.subnet_ids

  # Run a fixed number of instances in the ASG
  min_size             = var.cluster_size
  max_size             = var.cluster_size
  desired_capacity     = var.cluster_size
  termination_policies = [var.termination_policies]

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  service_linked_role_arn   = var.service_linked_role_arn

  enabled_metrics = var.enabled_metrics

  tags = flatten(
    [
      {
        key                 = "Name"
        value               = var.cluster_name
        propagate_at_launch = true
      },
      {
        key                 = var.cluster_tag_key
        value               = var.cluster_tag_value
        propagate_at_launch = true
      },
      var.tags,
    ]
  )
}

# Lookup most recent AMI
data "aws_ami" "latest-ubuntu" {
most_recent = true
owners = ["099720109477"] # Canonical

  filter {
      name   = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
      name   = "virtualization-type"
      values = ["hvm"]
  }
}

# Launch Configuration for Consul ASG
resource "aws_launch_configuration" "launch_configuration" {
  name_prefix   = "${var.cluster_name}-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.latest-ubuntu.id
  instance_type = var.instance_type != "" ? var.instance_type : lookup({"extra_small"="m4.large", "small"="m4.xlarge", "large"="m4.2xlarge", "extra_large"="m4.4xlarge"}, var.instance_size, "")
  user_data     = templatefile("${path.module}/scripts/install-consul.tpl",
    {
      version = var.consul_version,
      download-url = var.download-url,
      path         = var.path,
      user    = var.user,
      ca-file-path = var.ca-file-path,
      cert-file-path = var.cert-file-path,
      key-file-path = var.key-file-path,
      server  = var.server,
      client  = var.client,
      config-dir = var.config-dir,
      data-dir = var.data-dir,
      systemd-stdout = var.systemd-stdout,
      systemd-stderr = var.systemd-stderr,
      bin-dir = var.bin-dir,
      cluster-tag-key = var.cluster-tag-key,
      cluster-tag-value = var.cluster-tag-value,
      datacenter = var.datacenter,
      autopilot-cleanup-dead-servers = var.autopilot-cleanup-dead-servers,
      autopilot-last-contact-threshold = var.autopilot-last-contact-threshold,
      autopilot-max-trailing-logs = var.autopilot-max-trailing-logs,
      autopilot-server-stabilization-time = var.autopilot-server-stabilization-time,
      autopilot-redundancy-zone-tag = var.autopilot-redundancy-zone-tag,
      autopilot-disable-upgrade-migration = var.autopilot-disable-upgrade-migration,
      autopilot-upgrade-version-tag = var.autopilot-upgrade-version-tag,
      enable-gossip-encryption = var.enable-gossip-encryption,
      gossip-encryption-key = var.gossip-encryption-key,
      enable-rpc-encryption = var.enable-rpc-encryption,
      environment = var.environment,
      skip-consul-config = var.skip-consul-config,
      recursor = var.recursor,
    },
  )
  spot_price    = var.spot_price

  iam_instance_profile = var.enable_iam_setup ? element(
    concat(aws_iam_instance_profile.instance_profile.*.name, [""]),
    0,
  ) : var.iam_instance_profile_name
  key_name = var.ssh_key_name

  security_groups = concat(
    [aws_security_group.lc_security_group.id],
    var.additional_security_group_ids,
  )
  placement_tenancy           = var.tenancy
  associate_public_ip_address = var.associate_public_ip_address

  ebs_optimized = var.root_volume_ebs_optimized

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = var.root_volume_delete_on_termination
  }

  # Important note: whenever using a launch configuration with an auto scaling group, you must set
  # create_before_destroy = true. However, as soon as you set create_before_destroy = true in one resource, you must
  # also set it in every resource that it depends on, or you'll get an error about cyclic dependencies (especially when
  # removing resources). For more info, see:
  #
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  # https://terraform.io/docs/configuration/resources.html
  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Consul Cluster
resource "aws_security_group" "lc_security_group" {
  name_prefix = var.cluster_name
  description = "Security group for the ${var.cluster_name} launch configuration"
  vpc_id      = var.vpc_id

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    {
      "Name" = var.cluster_name
    },
    var.security_group_tags,
  )
}

resource "aws_security_group_rule" "allow_ssh_inbound" {
  count       = length(var.allowed_ssh_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.ssh_port
  to_port     = var.ssh_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_ssh_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_ssh_inbound_from_security_group_ids" {
  count                    = var.allowed_ssh_security_group_count
  type                     = "ingress"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_ssh_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.lc_security_group.id
}

# Consul Specific Security Group Rules
resource "aws_security_group_rule" "allow_server_rpc_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.server_rpc_port
  to_port     = var.server_rpc_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_cli_rpc_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.cli_rpc_port
  to_port     = var.cli_rpc_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_tcp_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.serf_wan_port
  to_port     = var.serf_wan_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_udp_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.serf_wan_port
  to_port     = var.serf_wan_port
  protocol    = "udp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_http_api_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.http_api_port
  to_port     = var.http_api_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_tcp_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.dns_port
  to_port     = var.dns_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_udp_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) >= 1 ? 1 : 0
  type        = "ingress"
  from_port   = var.dns_port
  to_port     = var.dns_port
  protocol    = "udp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_server_rpc_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.server_rpc_port
  to_port                  = var.server_rpc_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_cli_rpc_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.cli_rpc_port
  to_port                  = var.cli_rpc_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_tcp_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.serf_wan_port
  to_port                  = var.serf_wan_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_udp_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.serf_wan_port
  to_port                  = var.serf_wan_port
  protocol                 = "udp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_http_api_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.http_api_port
  to_port                  = var.http_api_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_tcp_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.dns_port
  to_port                  = var.dns_port
  protocol                 = "tcp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_udp_inbound_from_security_group_ids" {
  count                    = var.allowed_inbound_security_group_count
  type                     = "ingress"
  from_port                = var.dns_port
  to_port                  = var.dns_port
  protocol                 = "udp"
  source_security_group_id = element(var.allowed_inbound_security_group_ids, count.index)

  security_group_id = aws_security_group.lc_security_group.id
}

# Similar to the *_inbound_from_security_group_ids rules, allow inbound from ourself

resource "aws_security_group_rule" "allow_server_rpc_inbound_from_self" {
  type      = "ingress"
  from_port = var.server_rpc_port
  to_port   = var.server_rpc_port
  protocol  = "tcp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_cli_rpc_inbound_from_self" {
  type      = "ingress"
  from_port = var.cli_rpc_port
  to_port   = var.cli_rpc_port
  protocol  = "tcp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_tcp_inbound_from_self" {
  type      = "ingress"
  from_port = var.serf_wan_port
  to_port   = var.serf_wan_port
  protocol  = "tcp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_serf_wan_udp_inbound_from_self" {
  type      = "ingress"
  from_port = var.serf_wan_port
  to_port   = var.serf_wan_port
  protocol  = "udp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_http_api_inbound_from_self" {
  type      = "ingress"
  from_port = var.http_api_port
  to_port   = var.http_api_port
  protocol  = "tcp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_tcp_inbound_from_self" {
  type      = "ingress"
  from_port = var.dns_port
  to_port   = var.dns_port
  protocol  = "tcp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

resource "aws_security_group_rule" "allow_dns_udp_inbound_from_self" {
  type      = "ingress"
  from_port = var.dns_port
  to_port   = var.dns_port
  protocol  = "udp"
  self      = true

  security_group_id = aws_security_group.lc_security_group.id
}

# Create IAM policies
resource "aws_iam_instance_profile" "instance_profile" {
  count = var.enable_iam_setup ? 1 : 0

  name_prefix = var.cluster_name
  path        = var.instance_profile_path
  role        = element(concat(aws_iam_role.instance_role.*.name, [""]), 0)

  # aws_launch_configuration.launch_configuration in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "instance_role" {
  count = var.enable_iam_setup ? 1 : 0

  name_prefix        = var.cluster_name
  assume_role_policy = data.aws_iam_policy_document.instance_role.json

  # aws_iam_instance_profile.instance_profile in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "auto_discover_cluster" {
  count  = var.enable_iam_setup ? 1 : 0
  name   = "auto-discover-cluster"
  role   = element(concat(aws_iam_role.instance_role.*.id, [""]), 0)
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }
}
