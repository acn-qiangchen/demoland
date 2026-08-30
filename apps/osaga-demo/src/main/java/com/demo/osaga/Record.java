package com.demo.osaga;

/**
 * One CSV row. Input columns are {@code id,name,value}; the transform uppercases
 * {@code name} and stamps {@code processedAt}, which the writer emits as a fourth
 * {@code processed_at} column.
 */
public class Record {

    private String id;
    private String name;
    private String value;
    private String processedAt;
    private String batchTimestamp;
    private String appName;

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getValue() {
        return value;
    }

    public void setValue(String value) {
        this.value = value;
    }

    public String getProcessedAt() {
        return processedAt;
    }

    public void setProcessedAt(String processedAt) {
        this.processedAt = processedAt;
    }

    public String getBatchTimestamp() {
        return batchTimestamp;
    }

    public void setBatchTimestamp(String batchTimestamp) {
        this.batchTimestamp = batchTimestamp;
    }

    public String getAppName() {
        return appName;
    }

    public void setAppName(String appName) {
        this.appName = appName;
    }
}
