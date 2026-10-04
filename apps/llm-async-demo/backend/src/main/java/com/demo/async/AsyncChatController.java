package com.demo.async;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

/**
 * Request-and-forget + poll contract.
 *
 * <ul>
 *   <li>{@code POST /api/chat/async} — creates a job in the selected store, kicks the LLM call off in
 *       the background, and returns {@code 202} with the job id immediately.</li>
 *   <li>{@code GET /api/jobs/{jobId}?store=redis|dynamo} — returns the current job state; the browser
 *       polls this until status is COMPLETED or FAILED.</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class AsyncChatController {

    private static final Logger log = LoggerFactory.getLogger(AsyncChatController.class);

    private final OpenAiService openAiService;
    private final JobStoreResolver resolver;

    public AsyncChatController(OpenAiService openAiService, JobStoreResolver resolver) {
        this.openAiService = openAiService;
        this.resolver = resolver;
    }

    public record StartResponse(String jobId, String store, JobStatus status) {}

    public record ErrorResponse(String error) {}

    @PostMapping("/chat/async")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public Mono<StartResponse> startAsync(@RequestBody AsyncChatRequest request) {
        JobStore store = resolver.resolve(request.store());
        Job job = Job.create(store.name());

        return store.save(job)
                .doOnSuccess(v -> runInBackground(store, job, request.message()))
                .thenReturn(new StartResponse(job.jobId(), store.name(), job.status()));
    }

    @GetMapping("/jobs/{jobId}")
    public Mono<ResponseEntity<Job>> getJob(@PathVariable String jobId,
                                            @RequestParam(defaultValue = "redis") String store) {
        return resolver.resolve(store).find(jobId)
                .map(ResponseEntity::ok)
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    /**
     * Runs the LLM call off the request thread: mark PROCESSING, call OpenAI, then write COMPLETED
     * (or FAILED). Subscribed here so it outlives the HTTP response that already returned the job id.
     */
    private void runInBackground(JobStore store, Job job, String message) {
        store.save(job.processing())
                .then(openAiService.getFullResponse(message))
                .flatMap(result -> store.save(job.completed(result)))
                .onErrorResume(err -> {
                    log.warn("Job {} failed: {}", job.jobId(), err.toString());
                    return store.save(job.failed(err.getMessage()));
                })
                .subscribeOn(Schedulers.boundedElastic())
                .subscribe();
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleBadStore(IllegalArgumentException ex) {
        return ResponseEntity.badRequest().body(new ErrorResponse(ex.getMessage()));
    }
}
