package com.demo.async;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;

/**
 * Redis-backed job store (AWS ElastiCache in the deployed stack). Each job is stored as a JSON string
 * under {@code job:<id>} with a TTL so demo data self-cleans.
 */
@Component
public class RedisJobStore implements JobStore {

    private static final Duration TTL = Duration.ofHours(1);
    private static final String KEY_PREFIX = "job:";

    private final ReactiveStringRedisTemplate redis;
    private final ObjectMapper objectMapper;

    public RedisJobStore(ReactiveStringRedisTemplate redis, ObjectMapper objectMapper) {
        this.redis = redis;
        this.objectMapper = objectMapper;
    }

    @Override
    public String name() {
        return "redis";
    }

    @Override
    public Mono<Void> save(Job job) {
        return Mono.fromCallable(() -> objectMapper.writeValueAsString(job))
                .flatMap(json -> redis.opsForValue().set(KEY_PREFIX + job.jobId(), json, TTL))
                .then();
    }

    @Override
    public Mono<Job> find(String jobId) {
        return redis.opsForValue().get(KEY_PREFIX + jobId)
                .flatMap(json -> Mono.fromCallable(() -> objectMapper.readValue(json, Job.class)));
    }
}
