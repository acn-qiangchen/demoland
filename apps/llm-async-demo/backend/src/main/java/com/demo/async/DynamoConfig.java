package com.demo.async;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;

/**
 * Builds the DynamoDB async client. Credentials come from the default provider chain (the ECS task
 * role in the deployed stack); the region is taken from {@code aws.region} (defaults to us-east-1).
 */
@Configuration
public class DynamoConfig {

    @Bean(destroyMethod = "close")
    public DynamoDbAsyncClient dynamoDbAsyncClient(@Value("${aws.region:us-east-1}") String region) {
        return DynamoDbAsyncClient.builder()
                .region(Region.of(region))
                .build();
    }
}
