package com.demo.osaga;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.core.BatchStatus;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.JobExecution;
import org.springframework.batch.core.JobParameters;
import org.springframework.batch.core.JobParametersBuilder;
import org.springframework.batch.core.launch.JobLauncher;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.ExitCodeGenerator;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

/**
 * Orchestrates one run: download the input object from S3, run the Spring Batch
 * CSV transform against it, then upload the result to the output bucket. The exit
 * code (0 = job COMPLETED, 1 = anything else) is what Step Functions reads to drive
 * the saga's success / failure branches.
 *
 * <p>Local mode: if {@code INPUT_BUCKET} is unset, {@code INPUT_KEY} is treated as a
 * local file path and {@code OUTPUT_KEY} as the local output path — no S3, no AWS
 * credentials needed. Handy for running the pipeline against {@code sample-data/}.
 */
@Component
public class S3JobRunner implements ApplicationRunner, ExitCodeGenerator {

    private static final Logger log = LoggerFactory.getLogger(S3JobRunner.class);

    private final JobLauncher jobLauncher;
    private final Job csvTransformJob;
    private final JobProperties props;

    private int exitCode = 0;

    // Populated from command-line args in run(); threaded into launch().
    private String batchTimestamp;
    private String appName;

    public S3JobRunner(JobLauncher jobLauncher, Job csvTransformJob, JobProperties props) {
        this.jobLauncher = jobLauncher;
        this.csvTransformJob = csvTransformJob;
        this.props = props;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            // batch_timestamp / app_name arrive as plain named args (--batchTimestamp=… --appName=…),
            // passed EventBridge ($.time / literal) → Step Functions → ECS Command override → here.
            this.batchTimestamp = firstOption(args, "batchTimestamp");
            this.appName = firstOption(args, "appName");

            boolean localMode = props.getInputBucket() == null || props.getInputBucket().isBlank();
            if (localMode) {
                runLocal();
            } else {
                runWithS3();
            }
        } catch (Exception e) {
            // Never rethrow: swallow so SpringApplication.exit() reads getExitCode() below.
            // A non-zero code here becomes the container exit code → the saga's failure path.
            log.error("Batch run failed", e);
            exitCode = 1;
        }
    }

    private void runLocal() throws Exception {
        String inputFile = props.getInputKey();
        String outputFile = props.resolveOutputKey();
        log.info("Local mode: {} -> {}", inputFile, outputFile);
        launch(inputFile, outputFile);
    }

    private void runWithS3() throws Exception {
        // Work in a fresh temp dir; ResponseTransformer.toFile requires the target not to exist.
        Path workDir = Files.createTempDirectory("osaga-");
        Path inputFile = workDir.resolve("input.csv");
        Path outputFile = workDir.resolve("output.csv");
        String outputKey = props.resolveOutputKey();
        log.info("Processing s3://{}/{} -> s3://{}/{}",
                props.getInputBucket(), props.getInputKey(), props.getOutputBucket(), outputKey);

        try (S3Client s3 = S3Client.create()) {
            s3.getObject(GetObjectRequest.builder()
                            .bucket(props.getInputBucket())
                            .key(props.getInputKey())
                            .build(),
                    ResponseTransformer.toFile(inputFile));

            launch(inputFile.toString(), outputFile.toString());

            // Only publish on a clean run — a failed job must not leave a partial output object.
            if (exitCode == 0) {
                s3.putObject(PutObjectRequest.builder()
                                .bucket(props.getOutputBucket())
                                .key(outputKey)
                                .contentType("text/csv")
                                .build(),
                        RequestBody.fromFile(outputFile));
                log.info("Uploaded result to s3://{}/{}", props.getOutputBucket(), outputKey);
            }
        } finally {
            Files.deleteIfExists(inputFile);
            Files.deleteIfExists(outputFile);
            Files.deleteIfExists(workDir);
        }
    }

    private void launch(String inputFile, String outputFile) throws Exception {
        // These arrive as command-line args from EventBridge → Step Functions; when omitted
        // (e.g. local runs) fall back to sensible defaults (never pass null to addString).
        String batchTimestamp = this.batchTimestamp;
        if (batchTimestamp == null || batchTimestamp.isBlank()) {
            batchTimestamp = Instant.now().toString();
        }
        String appName = this.appName;
        if (appName == null || appName.isBlank()) {
            appName = "osaga-demo";
        }

        JobParameters params = new JobParametersBuilder()
                .addString("inputFile", inputFile)
                .addString("outputFile", outputFile)
                .addString("batchTimestamp", batchTimestamp)
                .addString("appName", appName)
                .addLong("run.id", System.currentTimeMillis()) // make each launch unique
                .toJobParameters();

        JobExecution exec = jobLauncher.run(csvTransformJob, params);
        if (exec.getStatus() != BatchStatus.COMPLETED) {
            log.error("Job did not complete: status={}", exec.getStatus());
            exitCode = 1;
        } else {
            log.info("Job completed: {} rows written", exec.getStepExecutions().stream()
                    .mapToLong(se -> se.getWriteCount()).sum());
        }
    }

    /** First value of a {@code --name=…} option, or {@code null} if the option is absent. */
    private static String firstOption(ApplicationArguments args, String name) {
        List<String> v = args.getOptionValues(name);
        return (v == null || v.isEmpty()) ? null : v.get(0);
    }

    @Override
    public int getExitCode() {
        return exitCode;
    }
}
