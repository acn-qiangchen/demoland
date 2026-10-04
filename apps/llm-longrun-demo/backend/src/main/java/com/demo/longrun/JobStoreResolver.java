package com.demo.longrun;

import org.springframework.stereotype.Component;

import java.util.Map;

/** Routes a request to the Redis or DynamoDB store based on the {@code store} value it carries. */
@Component
public class JobStoreResolver {

    private static final String DEFAULT_STORE = "redis";

    private final Map<String, JobStore> stores;

    public JobStoreResolver(RedisJobStore redis, DynamoJobStore dynamo) {
        this.stores = Map.of(redis.name(), redis, dynamo.name(), dynamo);
    }

    /** Resolve the store for the given key (null/blank falls back to redis). */
    public JobStore resolve(String store) {
        String key = (store == null || store.isBlank()) ? DEFAULT_STORE : store.toLowerCase();
        JobStore resolved = stores.get(key);
        if (resolved == null) {
            throw new IllegalArgumentException("Unknown store '" + store + "' (expected 'redis' or 'dynamo')");
        }
        return resolved;
    }
}
