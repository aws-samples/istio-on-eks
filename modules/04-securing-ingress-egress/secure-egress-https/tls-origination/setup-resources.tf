data "aws_region" "current_region" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpcs" "cluster_vpc" {
    
    filter {
        name = "tag:Name"
        values = ["eksctl-eksworkshop-VPC"]
    }
}

data "aws_vpc" "cluster_vpc_selected" {
  id = data.aws_vpcs.cluster_vpc.ids[0]
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

resource "aws_security_group" "allow_https_api" {
  name        = "allow_https_api"
  description = "Allow HTTPS inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.cluster_vpc_selected.id

  tags = {
    Name = "allow_https_api"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.allow_https_api.id
  cidr_ipv4         = data.aws_vpc.cluster_vpc_selected.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic" {
  security_group_id = aws_security_group.allow_https_api.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_endpoint" "istiosamplerestapivpcendpoint" {

  private_dns_enabled = true
  security_group_ids  = [aws_security_group.allow_https_api.id]
  service_name        = "com.amazonaws.${data.aws_region.current_region.name}.execute-api"
  subnet_ids          = flatten([for k, v in data.aws_subnets.cluster_private_subnets : v.ids])
  vpc_endpoint_type   = "Interface"
  vpc_id              = data.aws_vpc.cluster_vpc_selected.id
}

resource aws_api_gateway_rest_api istio_sample_restapi {
  
  name              = "sample_restapi"
  put_rest_api_mode = "merge"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.istiosamplerestapivpcendpoint.id]
  }
}

data "aws_iam_policy_document" "istio_sample_restapi_accesspolicy" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = [aws_api_gateway_rest_api.istio_sample_restapi.execution_arn]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = [data.aws_vpc.cluster_vpc_selected.cidr_block_associations[0].cidr_block]
    }
  }
}
resource "aws_api_gateway_rest_api_policy" "istio_sample_restapi_accessperm" {
  rest_api_id = aws_api_gateway_rest_api.istio_sample_restapi.id
  policy      = data.aws_iam_policy_document.istio_sample_restapi_accesspolicy.json
}

resource aws_api_gateway_resource istio_sample_restapi {
  rest_api_id = aws_api_gateway_rest_api.istio_sample_restapi.id
  parent_id = aws_api_gateway_rest_api.istio_sample_restapi.root_resource_id
  path_part = "sample"
}

resource aws_api_gateway_method istio_sample_restapi_get {
  rest_api_id = aws_api_gateway_resource.istio_sample_restapi.rest_api_id
  resource_id = aws_api_gateway_resource.istio_sample_restapi.id
  authorization = "NONE"
  http_method = "GET"
}

resource aws_api_gateway_integration istio_sample_restapi_get {
  rest_api_id = aws_api_gateway_method.istio_sample_restapi_get.rest_api_id
  resource_id = aws_api_gateway_method.istio_sample_restapi_get.resource_id
  http_method = aws_api_gateway_method.istio_sample_restapi_get.http_method
  type = "MOCK"
  request_templates = {
    "application/json" = <<TEMPLATE
{
  "statusCode": 200
}
TEMPLATE
  }
}

resource aws_api_gateway_method_response istio_sample_restapi_get {
  rest_api_id = aws_api_gateway_method.istio_sample_restapi_get.rest_api_id
  resource_id = aws_api_gateway_method.istio_sample_restapi_get.resource_id
  http_method = aws_api_gateway_method.istio_sample_restapi_get.http_method
  status_code = 200
}

resource aws_api_gateway_integration_response istio_sample_restapi_get {
  rest_api_id = aws_api_gateway_integration.istio_sample_restapi_get.rest_api_id
  resource_id = aws_api_gateway_integration.istio_sample_restapi_get.resource_id
  http_method = aws_api_gateway_integration.istio_sample_restapi_get.http_method
  status_code = 200
  response_templates = {
    "application/json" = <<TEMPLATE
{
    "response" : "Hello World!"
}
TEMPLATE
  }
}

resource aws_api_gateway_deployment istio_sample_restapi_get {
  depends_on = [aws_api_gateway_integration.istio_sample_restapi_get]
  rest_api_id = aws_api_gateway_rest_api.istio_sample_restapi.id
  description = "Deployed ${timestamp()}"

  stage_name = "dev"
}

output subnetIds {
  value = flatten([for k, v in data.aws_subnets.cluster_private_subnets : v.ids])
}

output sample_api_url {
  value = "${aws_api_gateway_deployment.istio_sample_restapi_get.invoke_url}/${aws_api_gateway_resource.istio_sample_restapi.path_part}"
}