package com.demo.osaga;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Batch entry point. This is NOT a web server — it runs one Spring Batch job on
 * startup and exits. The process exit code (driven by {@link S3JobRunner}, an
 * {@code ExitCodeGenerator}) is what Step Functions inspects: a failed job exits
 * non-zero, which surfaces as a failed ECS task and drives the saga's Catch path.
 */
@SpringBootApplication
public class OsagaDemoApplication {
    public static void main(String[] args) {
        // SpringApplication.exit() collects the ExitCodeGenerator beans (S3JobRunner)
        // and returns their code; System.exit propagates it to the container runtime.
        System.exit(SpringApplication.exit(SpringApplication.run(OsagaDemoApplication.class, args)));
    }
}
