package com.demo.async;

/** Lifecycle of an async LLM job: PENDING → PROCESSING → COMPLETED (or FAILED). */
public enum JobStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED
}
