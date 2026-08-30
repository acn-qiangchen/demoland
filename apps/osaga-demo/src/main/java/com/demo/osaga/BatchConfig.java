package com.demo.osaga;

import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.item.file.FlatFileItemReader;
import org.springframework.batch.item.file.FlatFileItemWriter;
import org.springframework.batch.item.file.builder.FlatFileItemReaderBuilder;
import org.springframework.batch.item.file.builder.FlatFileItemWriterBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.FileSystemResource;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Defines the single-step CSV transform job. The reader/writer are {@code @StepScope}
 * so their file paths bind late from the {@code inputFile}/{@code outputFile} job
 * parameters that {@link S3JobRunner} supplies after downloading the S3 object.
 */
@Configuration
public class BatchConfig {

    static final String JOB_NAME = "csvTransformJob";
    private static final String[] INPUT_FIELDS = {"id", "name", "value"};
    private static final String OUTPUT_HEADER = "id,name,value,processed_at,batch_timestamp,app_name";

    @Bean
    @StepScope
    public FlatFileItemReader<Record> reader(@Value("#{jobParameters['inputFile']}") String inputFile) {
        return new FlatFileItemReaderBuilder<Record>()
                .name("recordReader")
                .resource(new FileSystemResource(inputFile))
                .linesToSkip(1) // skip the header row
                .delimited()
                .names(INPUT_FIELDS)
                .targetType(Record.class)
                .build();
    }

    @Bean
    @StepScope
    public FlatFileItemWriter<Record> writer(@Value("#{jobParameters['outputFile']}") String outputFile) {
        return new FlatFileItemWriterBuilder<Record>()
                .name("recordWriter")
                .resource(new FileSystemResource(outputFile))
                .headerCallback(w -> w.write(OUTPUT_HEADER))
                .delimited()
                .names("id", "name", "value", "processedAt", "batchTimestamp", "appName")
                .build();
    }

    @Bean
    @StepScope
    public RecordProcessor processor(
            @Value("#{jobParameters['batchTimestamp']}") String batchTimestamp,
            @Value("#{jobParameters['appName']}") String appName) {
        return new RecordProcessor(batchTimestamp, appName);
    }

    @Bean
    public Step transformStep(JobRepository jobRepository,
                              PlatformTransactionManager txManager,
                              FlatFileItemReader<Record> reader,
                              RecordProcessor processor,
                              FlatFileItemWriter<Record> writer) {
        return new StepBuilder("transformStep", jobRepository)
                .<Record, Record>chunk(100, txManager)
                .reader(reader)
                .processor(processor)
                .writer(writer)
                .build();
    }

    @Bean
    public Job csvTransformJob(JobRepository jobRepository, Step transformStep) {
        return new JobBuilder(JOB_NAME, jobRepository)
                .start(transformStep)
                .build();
    }
}
