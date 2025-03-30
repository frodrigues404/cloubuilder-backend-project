module "cost_tracker_dynamodb" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "4.1.0"

  name      = "aws_costs"
  hash_key  = "pk"
  range_key = "sk"

  attributes = [
    {
      name = "pk"
      type = "S"
    },
    {
      name = "sk"
      type = "S"
    }
  ]

  tags = local.tags
}

module "cost_tracker_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.9.0"

  function_name                           = "lambda_cost_tracker"
  description                             = "Save Costs In DynamoDB"
  handler                                 = "main.handler"
  runtime                                 = "provided.al2023"
  attach_policy_json                      = true
  tracing_mode                            = "Active"
  attach_tracing_policy                   = true
  create_current_version_allowed_triggers = false
  timeout                                 = 120
  architectures                           = ["arm64"]

  environment_variables = {
    TABLE_NAME = module.cost_tracker_dynamodb.dynamodb_table_id
    REGION     = var.region
  }

  policy_json = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:Scan"
            ],
            "Resource": "${module.cost_tracker_dynamodb.dynamodb_table_arn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage"
            ],
            "Resource": "*"
        }
    ]
}
EOF
  source_path = [
    {
      path = "${path.module}/cost-tracker"
      commands = [
        "GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o bootstrap main.go",
        ":zip",
      ]
      patterns = [
        "!.*",
        "bootstrap",
      ]
    }
  ]

  tags = local.tags
}

module "api_gateway" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "5.2.0"

  name                  = "${var.project}-${var.environment}-api"
  description           = "${var.project} project API"
  protocol_type         = "HTTP"
  create_certificate    = false
  create_domain_name    = false
  create_domain_records = false

  routes = {
    "GET /week-costs" = {
      integration = {
        uri = module.cost_tracker_lambda.lambda_function_arn
      }
    },
  }

  tags = local.tags
}