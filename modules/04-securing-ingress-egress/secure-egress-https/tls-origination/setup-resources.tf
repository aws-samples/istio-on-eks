data "aws_region" "current_region" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpcs" "cluster_vpc" {
    
    filter {
        name = "tag:Name"
        values = ["istio"]
    }
}

data "aws_subnets" "cluster_private_subnets" {
    for_each = toset(data.aws_availability_zones.available.zone_ids)

    filter {
        name   = "vpc-id"
        values = [data.aws_vpcs.cluster_vpc.ids[0]]
    }
  
    filter {
        name = "tag:kubernetes.io/role/internal-elb"
        values = ["1"]
    }

    filter {
        name = "availability-zone-id"
        values = ["${each.value}"]
    }
}


