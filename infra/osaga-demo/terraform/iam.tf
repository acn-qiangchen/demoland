# ===========================================================================
# ECS roles
# ===========================================================================

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---- Task execution role: ECR pull + CloudWatch Logs ----
resource "aws_iam_role" "execution" {
  name               = "${var.app_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---- Task role: what the batch app itself may do — read input, write output ----
resource "aws_iam_role" "task" {
  name               = "${var.app_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task_s3" {
  statement {
    sid       = "ReadInput"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }
  statement {
    sid       = "ListInput"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.input.arn]
  }
  statement {
    sid       = "WriteOutput"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }
}

resource "aws_iam_role_policy" "task_s3" {
  name   = "${var.app_name}-task-s3"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_s3.json
}

# ===========================================================================
# Step Functions role
# ===========================================================================

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.app_name}-sfn"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn" {
  # Run + manage the Fargate task.
  statement {
    sid       = "RunTask"
    actions   = ["ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["*"]
  }

  # Pass the execution + task roles to ECS when starting the task.
  statement {
    sid       = "PassEcsRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
  }

  # ecs:runTask.sync needs a managed EventBridge rule to receive task-state-change
  # events; Step Functions creates/manages it on the caller's behalf.
  statement {
    sid = "EventsForSync"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule",
    ]
    resources = ["arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${var.app_name}-sfn-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

# ===========================================================================
# EventBridge rule role: lets the S3 "Object Created" rule start an execution
# ===========================================================================

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.app_name}-events"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events" {
  statement {
    sid       = "StartSaga"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.this.arn]
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "${var.app_name}-events-policy"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events.json
}

data "aws_caller_identity" "current" {}
