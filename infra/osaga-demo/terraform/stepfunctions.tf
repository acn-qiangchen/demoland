# The saga orchestrator. A single synchronous ECS task, with Retry (transient
# faults) and Catch (permanent failure → the Failed terminal state). runTask.sync
# blocks until the Fargate task exits, so a non-zero container exit surfaces here as
# a States.TaskFailed and routes down the Catch path — that Retry/Catch pair is the
# saga's success / compensation logic.
resource "aws_sfn_state_machine" "this" {
  name     = var.app_name
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "osaga-demo: run the Spring Batch CSV transform on Fargate, waiting for completion."
    StartAt = "EnsureOutputFileName"
    States = {
      # outputFileName is optional in the execution input. Normalise it to an empty string
      # when absent so RunEcsTask can always reference $.outputFileName safely; the app
      # treats a blank value as "not supplied" and keeps the default output naming.
      EnsureOutputFileName = {
        Type = "Choice"
        Choices = [
          {
            Variable  = "$.outputFileName"
            IsPresent = true
            Next      = "RunEcsTask"
          }
        ]
        Default = "DefaultOutputFileName"
      }
      DefaultOutputFileName = {
        Type       = "Pass"
        Result     = ""
        ResultPath = "$.outputFileName"
        Next       = "RunEcsTask"
      }
      RunEcsTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          Cluster        = aws_ecs_cluster.this.arn
          TaskDefinition = aws_ecs_task_definition.this.arn
          LaunchType     = "FARGATE"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets = aws_subnet.public[*].id
              # Public IP so the task can reach ECR + S3 + CloudWatch without a NAT gateway.
              AssignPublicIp = "ENABLED"
              SecurityGroups = [aws_security_group.task.id]
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = var.app_name
                Environment = [
                  { Name = "INPUT_BUCKET", "Value.$" = "$.inputBucket" },
                  { Name = "INPUT_KEY", "Value.$" = "$.inputKey" },
                  { Name = "OUTPUT_BUCKET", Value = aws_s3_bucket.output.bucket },
                ]
                # batch_timestamp / app_name / outputFileName reach the app as plain command-line
                # args, appended to the Dockerfile ENTRYPOINT (ECS command → Docker CMD). Values
                # come from the SFN input, so build the array with intrinsics via the .$ form.
                # outputFileName is normalised to "" upstream, so --outputFileName= is harmless.
                "Command.$" = "States.Array(States.Format('--batchTimestamp={}', $.batchTimestamp), States.Format('--appName={}', $.appName), States.Format('--outputFileName={}', $.outputFileName))"
              }
            ]
          }
        }
        Retry = [
          {
            # Transient AWS-side faults only — retry with backoff before giving up.
            ErrorEquals = [
              "ECS.AmazonECSException",
              "States.TaskFailed.ServiceUnavailable",
              "States.Timeout",
            ]
            IntervalSeconds = 5
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "Failed"
          }
        ]
        Next = "Succeeded"
      }
      Succeeded = {
        Type = "Succeed"
      }
      Failed = {
        Type  = "Fail"
        Error = "BatchTaskFailed"
        Cause = "The ECS Fargate batch task did not complete successfully."
      }
    }
  })

  tags = { Name = "${var.app_name}-sfn" }
}
