data "aws_caller_identity" "this" {}
data "aws_ssm_parameter" "db_password" {
  name = "DB_PASSWORD"
}

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "${local.prefix}-vpc"
  cidr               = local.vpc_cidr_block
  azs                = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  enable_nat_gateway = false
  enable_vpn_gateway = false
}

resource "aws_security_group" "this" {
  name = "${local.prefix}-sg"
  tags = {
    "Name" = "${local.prefix}-sg"
  }
  vpc_id      = module.vpc.vpc_id
  description = "Security Group for Aurora"
  egress = [
    {
      cidr_blocks = [
        "0.0.0.0/0",
      ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 65535
    }
  ]
  ingress = [
    {
      cidr_blocks = [
        local.vpc_cidr_block
      ]
      description      = ""
      from_port        = 3306
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 3306
    },
  ]
}

resource "aws_db_subnet_group" "this" {
  description = "DBSubnets for Aurora"
  name        = "${local.prefix}-db-subnet-group"
  subnet_ids  = module.vpc.private_subnets
}

resource "aws_rds_cluster_parameter_group" "this" {
  description = "DBClusterParameterGroup for Aurora Cluster"
  family      = local.parmeter_group_family
  name        = "${local.prefix}-aurora-cluster-parameter-group"
  tags = {
    "Name" = "${local.prefix}-cluster-parameter-group"
  }
  parameter {
    apply_method = "immediate"
    name         = "server_audit_events"
    value        = "QUERY"
  }
  parameter {
    apply_method = "immediate"
    name         = "server_audit_logging"
    value        = "1"
  }
  parameter {
    apply_method = "immediate"
    name         = "time_zone"
    value        = "Asia/Tokyo"
  }
}

resource "aws_db_parameter_group" "this" {
  description = "DBParameterGroup for Aurora instance"
  family      = local.parmeter_group_family
  name        = "${local.prefix}-db-parameter-group"
  tags = {
    "Name" = "${local.prefix}-db-parameter-group"
  }

  parameter {
    apply_method = "immediate"
    name         = "general_log"
    value        = "1"
  }
  parameter {
    apply_method = "immediate"
    name         = "long_query_time"
    value        = "1"
  }
  parameter {
    apply_method = "immediate"
    name         = "slow_query_log"
    value        = "1"
  }
}

resource "aws_kms_key" "this" {
  description             = "Key for encrypting aurora"
  policy = jsonencode(
    {
      Statement = [
        {
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : "arn:aws:iam::${data.aws_caller_identity.this.account_id}:root"
          },
          "Action" : "kms:*",
          "Resource" : "*"
        },
      ]
      Version = "2012-10-17"
    }
  )
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.prefix}-aencrypt-key"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_rds_cluster" "this" {
  engine          = "aurora-mysql"
  engine_mode     = "provisioned"
  engine_version  = local.engine_version
  master_username = local.master_username
  master_password = data.aws_ssm_parameter.db_password.value
  port            = 3306
  availability_zones = [
    "ap-northeast-1a",
    "ap-northeast-1c",
    "ap-northeast-1d",
  ]
  cluster_identifier              = "${local.prefix}-cluster"
  backup_retention_period         = local.backup_retention_period
  copy_tags_to_snapshot           = false
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  db_subnet_group_name            = aws_db_subnet_group.this.name
  deletion_protection             = true
  enabled_cloudwatch_logs_exports = [
    "audit",
    "error",
    "general",
    "slowquery",
  ]
  preferred_backup_window      = "18:00-18:30"
  preferred_maintenance_window = "sun:17:00-sun:17:30"
  skip_final_snapshot          = true
  storage_encrypted            = true
  kms_key_id                   = aws_kms_key.this.arn
  tags = {
    "Name" = "${local.prefix}-cluster"
  }
  vpc_security_group_ids = [
    aws_security_group.this.id,
  ]
  serverlessv2_scaling_configuration {
    min_capacity = local.min_capacity
    max_capacity = local.max_capacity
  }
  lifecycle {
    ignore_changes = [
      availability_zones,
    ]
  }
}

resource "aws_rds_cluster_instance" "provisioned" {
  count                        = local.provisioned.count
  identifier                   = "${local.prefix}-instance-provisioned-${count.index}"
  cluster_identifier           = aws_rds_cluster.this.id
  instance_class               = local.provisioned.instance_class
  engine                       = aws_rds_cluster.this.engine
  engine_version               = aws_rds_cluster.this.engine_version
  db_parameter_group_name      = aws_db_parameter_group.this.name
  auto_minor_version_upgrade   = false
  performance_insights_enabled = local.provisioned.performance_insights_enabled
}

resource "aws_rds_cluster_instance" "serverless" {
  # Create Provisioned instance first so that Provisioned becomes a writer
  depends_on                   = [aws_rds_cluster_instance.provisioned]
  count                        = local.serverless.count
  identifier                   = "${local.prefix}-aurora-instance-serverless-${count.index}"
  cluster_identifier           = aws_rds_cluster.this.id
  instance_class               = local.serverless.instance_class
  engine                       = aws_rds_cluster.this.engine
  engine_version               = aws_rds_cluster.this.engine_version
  db_parameter_group_name      = aws_db_parameter_group.this.name
  auto_minor_version_upgrade   = false
  performance_insights_enabled = local.serverless.performance_insights_enabled
}