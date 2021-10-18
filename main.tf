data "aws_ecs_cluster" "existing" {
  cluster_name = "jb_cluster"
}

locals {
  ecs_cluster_arn = data.aws_ecs_cluster.existing.arn
}

resource "aws_iam_role" "run_tak_role" {
  name               = "run_tak_role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }, {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "events.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "policy" {
  name        = "RunTaskPolicy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ecs:RunTask"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : "iam:PassRole",
        "Resource" : [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.run_tak_role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_cloudwatch_log_group" "logs-generator" {
  name = "logs-generator"
}

data "aws_ssm_parameter" "youtrack_url" {
  name = "youtrack_url"
}

data "aws_ssm_parameter" "youtrack_token" {
  name = "youtrack_token"
}

resource "aws_ecs_task_definition" "generator" {
  family                = "generator"
  task_role_arn         = aws_iam_role.run_tak_role.arn
  container_definitions = jsonencode([
    {
      name : "generator",
      image : "ildaryap/generator:1",
      essential : true,
      logConfiguration : {
        "logDriver" : "awslogs",
        "options" : {
          "awslogs-group" : aws_cloudwatch_log_group.logs-generator.name,
          "awslogs-region" : "us-east-2",
          "awslogs-stream-prefix" : "logs-generator"
        }
      },
      environment : [
        {
          name : "MAX_TASKS",
          value : var.max_tasks
        }, {
          name : "MAX_COMMENTS",
          value : var.max_comments
        }, {
          name : "YOUTRACK_URL",
          value : data.aws_ssm_parameter.youtrack_url.value
        }, {
          name : "YOUTRACK_TOKEN",
          value : data.aws_ssm_parameter.youtrack_token.value
        }
      ]
      memory : 256,
      cpu : 256
    }
  ])
  cpu                   = 256
  memory                = 256
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  name                = "generator"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {

  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "generator"
  arn       = local.ecs_cluster_arn

  role_arn = aws_iam_role.run_tak_role.arn
  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.generator.arn
  }
}