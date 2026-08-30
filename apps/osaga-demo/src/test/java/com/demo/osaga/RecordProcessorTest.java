package com.demo.osaga;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class RecordProcessorTest {

    private static final String TIMESTAMP = "2026-08-30T12:00:00Z";
    private final RecordProcessor processor = new RecordProcessor(TIMESTAMP, "osaga-demo");

    @Test
    void uppercasesNameAndStampsProcessedAt() {
        Record in = new Record();
        in.setId("1");
        in.setName("alice");
        in.setValue("100");

        Record out = processor.process(in);

        assertThat(out.getId()).isEqualTo("1");
        assertThat(out.getName()).isEqualTo("ALICE");
        assertThat(out.getValue()).isEqualTo("100");
        assertThat(out.getProcessedAt()).isNotBlank();
        assertThat(out.getBatchTimestamp()).isEqualTo(TIMESTAMP);
        assertThat(out.getAppName()).isEqualTo("osaga-demo");
    }

    @Test
    void toleratesNullName() {
        Record in = new Record();
        in.setId("2");

        Record out = processor.process(in);

        assertThat(out.getName()).isNull();
        assertThat(out.getProcessedAt()).isNotBlank();
    }
}
