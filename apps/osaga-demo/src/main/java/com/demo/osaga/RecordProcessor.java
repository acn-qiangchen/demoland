package com.demo.osaga;

import java.time.Instant;
import org.springframework.batch.item.ItemProcessor;

/**
 * The transform: uppercase the {@code name} column and stamp each row with the
 * processing time (emitted as the {@code processed_at} column by the writer).
 */
public class RecordProcessor implements ItemProcessor<Record, Record> {

    private final String batchTimestamp;
    private final String appName;

    public RecordProcessor(String batchTimestamp, String appName) {
        this.batchTimestamp = batchTimestamp;
        this.appName = appName;
    }

    @Override
    public Record process(Record item) {
        Record out = new Record();
        out.setId(item.getId());
        out.setName(item.getName() == null ? null : item.getName().toUpperCase());
        out.setValue(item.getValue());
        out.setProcessedAt(Instant.now().toString());
        out.setBatchTimestamp(batchTimestamp);
        out.setAppName(appName);
        return out;
    }
}
