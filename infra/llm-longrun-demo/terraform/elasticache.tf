# ElastiCache for Valkey — the Redis-compatible job store. Valkey is the Linux Foundation fork AWS
# now positions as the forward path after Redis's 2024 license change; it speaks the same RESP wire
# protocol, so the Lettuce / Spring Data Redis client needs no changes. Single-node (no replication/
# cluster mode); sufficient for a demo. Reachable only from the ECS tasks via the redis security group.
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.app_name}-redis-subnets"
  subnet_ids = aws_subnet.public[*].id

  tags = { Name = "${var.app_name}-redis-subnets" }
}

# Valkey is only supported on the replication-group resource (not aws_elasticache_cluster). We run a
# single node — num_cache_clusters = 1, no replicas, no failover — which is the non-serverless Valkey
# equivalent of a one-node cluster. Transit encryption is left off so the client connects over
# plaintext 6379 (serverless Valkey would force TLS and a client-side SSL change).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.app_name}-redis"
  description          = "Valkey job store for ${var.app_name}"
  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  parameter_group_name = "default.valkey8"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  automatic_failover_enabled = false

  tags = { Name = "${var.app_name}-redis" }
}
