package com.demo.async;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

/**
 * DynamoDB-backed job store. Each job is one item keyed by {@code jobId}, with a {@code ttl} epoch-
 * seconds attribute (DynamoDB TTL enabled on the table) so demo data self-cleans.
 */
@Component
public class DynamoJobStore implements JobStore {

    private static final long TTL_SECONDS = 3600;

    private final DynamoDbAsyncClient dynamo;
    private final String tableName;

    public DynamoJobStore(DynamoDbAsyncClient dynamo,
                          @Value("${jobs.table-name}") String tableName) {
        this.dynamo = dynamo;
        this.tableName = tableName;
    }

    @Override
    public String name() {
        return "dynamo";
    }

    @Override
    public Mono<Void> save(Job job) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("jobId", s(job.jobId()));
        item.put("status", s(job.status().name()));
        item.put("store", s(job.store()));
        item.put("createdAt", n(job.createdAt()));
        item.put("completedAt", n(job.completedAt()));
        item.put("ttl", n(Instant.now().getEpochSecond() + TTL_SECONDS));
        if (job.result() != null) {
            item.put("result", s(job.result()));
        }
        if (job.error() != null) {
            item.put("error", s(job.error()));
        }

        return Mono.fromFuture(() -> dynamo.putItem(b -> b.tableName(tableName).item(item))).then();
    }

    @Override
    public Mono<Job> find(String jobId) {
        return Mono.fromFuture(() -> dynamo.getItem(b -> b.tableName(tableName)
                        .key(Map.of("jobId", s(jobId)))))
                .flatMap(resp -> resp.hasItem() ? Mono.just(toJob(resp.item())) : Mono.empty());
    }

    private static Job toJob(Map<String, AttributeValue> item) {
        return new Job(
                str(item, "jobId"),
                JobStatus.valueOf(str(item, "status")),
                str(item, "result"),
                str(item, "error"),
                str(item, "store"),
                num(item, "createdAt"),
                num(item, "completedAt"));
    }

    private static AttributeValue s(String v) {
        return AttributeValue.builder().s(v).build();
    }

    private static AttributeValue n(long v) {
        return AttributeValue.builder().n(Long.toString(v)).build();
    }

    private static String str(Map<String, AttributeValue> item, String key) {
        AttributeValue v = item.get(key);
        return v == null ? null : v.s();
    }

    private static long num(Map<String, AttributeValue> item, String key) {
        AttributeValue v = item.get(key);
        return v == null || v.n() == null ? 0L : Long.parseLong(v.n());
    }
}
