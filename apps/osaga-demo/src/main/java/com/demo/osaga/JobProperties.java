package com.demo.osaga;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Binds the S3 coordinates supplied by Step Functions as container env overrides
 * (INPUT_BUCKET / INPUT_KEY / OUTPUT_BUCKET / OUTPUT_KEY). Relaxed binding maps the
 * uppercase env vars onto these camelCase fields.
 *
 * <p>If OUTPUT_KEY is left unset, it defaults to {@code processed/<input-filename>}.
 */
@Component
@ConfigurationProperties(prefix = "job")
public class JobProperties {

    private String inputBucket;
    private String inputKey;
    private String outputBucket;
    private String outputKey;

    /** Effective output key, defaulting to {@code processed/<input-filename>}. */
    public String resolveOutputKey() {
        if (outputKey != null && !outputKey.isBlank()) {
            return outputKey;
        }
        String name = inputKey == null ? "output.csv" : inputKey.substring(inputKey.lastIndexOf('/') + 1);
        return "processed/" + name;
    }

    public String getInputBucket() {
        return inputBucket;
    }

    public void setInputBucket(String inputBucket) {
        this.inputBucket = inputBucket;
    }

    public String getInputKey() {
        return inputKey;
    }

    public void setInputKey(String inputKey) {
        this.inputKey = inputKey;
    }

    public String getOutputBucket() {
        return outputBucket;
    }

    public void setOutputBucket(String outputBucket) {
        this.outputBucket = outputBucket;
    }

    public String getOutputKey() {
        return outputKey;
    }

    public void setOutputKey(String outputKey) {
        this.outputKey = outputKey;
    }
}
