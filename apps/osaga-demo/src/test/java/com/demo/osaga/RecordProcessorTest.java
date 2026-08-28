package com.demo.osaga;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class RecordProcessorTest {

    private final RecordProcessor processor = new RecordProcessor();

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
