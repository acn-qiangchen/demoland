package com.demo.longrun;

import java.time.Instant;
import java.util.UUID;

/**
 * A single async LLM job. Immutable — the lifecycle helpers return a new instance for each state
 * transition. {@code createdAt} / {@code completedAt} are epoch milliseconds ({@code completedAt} is
 * 0 until the job finishes). Serialized to JSON for Redis and mapped attribute-by-attribute for
 * DynamoDB.
 */
public record Job(
        String jobId,
        JobStatus status,
        String result,
        String error,
        String store,
        long createdAt,
        long completedAt) {

    public static Job create(String store) {
        return new Job(UUID.randomUUID().toString(), JobStatus.PENDING, null, null, store,
                Instant.now().toEpochMilli(), 0L);
    }

    public Job processing() {
        return new Job(jobId, JobStatus.PROCESSING, null, null, store, createdAt, 0L);
    }

    public Job completed(String result) {
        return new Job(jobId, JobStatus.COMPLETED, result, null, store, createdAt,
                Instant.now().toEpochMilli());
    }

    public Job failed(String error) {
        return new Job(jobId, JobStatus.FAILED, null, error, store, createdAt,
                Instant.now().toEpochMilli());
    }
}
