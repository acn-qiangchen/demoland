package com.demo.longrun;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.codec.ServerSentEvent;
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
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

/**
 * One controller, one story: a long-running LLM call that would blow a request timeout, and the two
 * standard ways to fix it. Every endpoint lives under {@code /api}:
 *
 * <ul>
 *   <li>{@code POST /api/chat/sync} — <b>the problem.</b> Blocks until the LLM finishes, holding the
 *       connection open with no bytes flowing. A long answer trips the ALB idle timeout on the
 *       deployed path (a 504).</li>
 *   <li>{@code POST /api/chat} — <b>fix 1 (SSE streaming).</b> Streams tokens as a
 *       {@code text/event-stream}; each token resets the ALB idle timer, so the connection survives.</li>
 *   <li>{@code POST /api/chat/async} — <b>fix 2 (async start).</b> Creates a job, kicks the LLM call
 *       off in the background, and returns {@code 202} with the job id immediately.</li>
 *   <li>{@code GET /api/jobs/{jobId}?store=redis|dynamo} — <b>fix 2 (poll).</b> Returns the current
 *       job state; the browser polls this until COMPLETED or FAILED.</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class ChatController {

    private static final Logger log = LoggerFactory.getLogger(ChatController.class);

    private final OpenAiService openAiService;
    private final JobStoreResolver resolver;

    public ChatController(OpenAiService openAiService, JobStoreResolver resolver) {
        this.openAiService = openAiService;
        this.resolver = resolver;
    }

    /**
     * Token payload sent as the SSE {@code data:} field. Encoding the token as JSON (rather than the
     * raw string) is deliberate: the SSE text protocol strips a single leading space after {@code data:}
     * and splits embedded newlines across multiple {@code data:} lines, which would silently drop
     * inter-word spaces and line breaks. JSON preserves both exactly.
     */
    public record TokenChunk(String content) {}

    /** Full response payload returned by the blocking sync endpoint. */
    public record FullResponse(String content) {}

    public record StartResponse(String jobId, String store, JobStatus status) {}

    public record ErrorResponse(String error) {}

    // ---- Fix 1: SSE streaming ----

    @PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<Object>> chat(@RequestBody ChatRequest request) {

        Flux<ServerSentEvent<Object>> tokenStream = openAiService
                .streamResponse(request.message())
                .map(token -> ServerSentEvent.<Object>builder()
                        .event("token")
                        .data(new TokenChunk(token)) // serialized as {"content":"..."}
                        .build());

        Flux<ServerSentEvent<Object>> doneEvent = Flux.just(
                ServerSentEvent.<Object>builder()
                        .event("done")
                        .data("[DONE]")
                        .build());

        // concat (not merge) guarantees [DONE] arrives after all tokens
        return Flux.concat(tokenStream, doneEvent);
    }

    // ---- The problem: blocking baseline ----

    /**
     * Synchronous blocking endpoint: no job store involved. Blocks until the LLM finishes generating,
     * then returns the full answer as a single {@code {"content":"..."}} body. This is the baseline the
     * two fixes contrast against — the request is held open the whole time it generates, so a long
     * answer trips the ALB idle timeout on the deployed path (a 504), whereas the SSE stream keeps the
     * connection alive byte-by-byte and the async submit + poll requests each return well under that limit.
     */
    @PostMapping("/chat/sync")
    public Mono<FullResponse> chatSync(@RequestBody ChatRequest request) {
        return openAiService.getFullResponse(request.message())
                .map(FullResponse::new);
    }

    // ---- Fix 2: async start + poll ----

    @PostMapping("/chat/async")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public Mono<StartResponse> startAsync(@RequestBody ChatRequest request) {
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
