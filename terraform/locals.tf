locals {
  prefix                  = "aurora-sample"
  vpc_cidr_block          = "10.0.0.0/16"
  aurora_mysql_version    = "8.0"
  parmeter_group_family   = "aurora-mysql${local.aurora_mysql_version}"
  backup_retention_period = 1
  engine_version          = "8.0.mysql_aurora.3.02.0"
  master_username         = "admin"
  min_capacity            = 0.5
  max_capacity            = 1.0
  # Aurora MySQL 3, db.t3.medium or t4g.medium is the minimum.
  provisioned = {
    count                        = 1
    instance_class               = "db.t4g.medium"
    performance_insights_enabled = false
  }
  serverless = {
    count                        = 1
    instance_class               = "db.serverless"
    performance_insights_enabled = false
  }
}