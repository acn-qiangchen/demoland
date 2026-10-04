package com.demo.async;

import reactor.core.publisher.Mono;

/**
 * A pluggable store for async jobs. Two implementations coexist at runtime — {@link RedisJobStore}
 * and {@link DynamoJobStore} — and the caller picks one per request via {@link JobStoreResolver}.
 */
public interface JobStore {

    /** The key used to select this store ("redis" / "dynamo"). */
    String name();

    /** Persist (create or overwrite) a job. */
    Mono<Void> save(Job job);

    /** Fetch a job by id, or an empty Mono if it does not exist. */
    Mono<Job> find(String jobId);
}
