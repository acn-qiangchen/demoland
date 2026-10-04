package com.demo.bff;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * BFF relay for the long-running LLM demo. Every endpoint mirrors the backend contract so the frontend
 * needs no path changes — only its origin points here.
 *
 * <ul>
 *   <li>{@code POST /api/chat}      → <b>fix 1 (SSE)</b>: streams the backend's {@code text/event-stream}
 *       through byte-by-byte so tokens surface progressively.</li>
 *   <li>{@code POST /api/chat/sync} → <b>the problem</b>: forwards the blocking JSON call and returns
 *       the full payload once generation completes.</li>
 *   <li>{@code POST /api/chat/async} → <b>fix 2 (start)</b>: forwards the start request, returns the
 *       backend's job id (202).</li>
 *   <li>{@code GET /api/jobs/{jobId}?store=…} → <b>fix 2 (poll)</b>: forwards the poll request.</li>
 * </ul>
 *
 * Upstream responses for the non-streaming endpoints (including non-2xx status and JSON body) are
 * passed through unchanged so the browser sees the backend's real status codes (202 / 200 / 404 / 400).
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class RelayController {

    private static final Logger log = LoggerFactory.getLogger(RelayController.class);

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final String backendBaseUrl;

    public RelayController(RestTemplate llmRestTemplate,
                           ObjectMapper objectMapper,
                           LlmClientProperties props) {
        this.restTemplate = llmRestTemplate;
        this.objectMapper = objectMapper;
        this.backendBaseUrl = props.getService().getBaseUrl();
    }

    // ---- Fix 1: SSE streaming ----

    /**
     * Streams the backend SSE response straight to the browser. We read the upstream byte stream in
     * small chunks and flush each one, so tokens surface progressively — the RestTemplate response
     * is streamed, not buffered.
     */
    @PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public StreamingResponseBody chat(@RequestBody ChatRequest request) {
        final String url = backendBaseUrl + "/api/chat";

        return clientOut -> restTemplate.execute(
                url,
                HttpMethod.POST,
                req -> {
                    req.getHeaders().setContentType(MediaType.APPLICATION_JSON);
                    req.getHeaders().setAccept(List.of(MediaType.TEXT_EVENT_STREAM));
                    objectMapper.writeValue(req.getBody(), request);
                },
                resp -> {
                    try (InputStream upstream = resp.getBody()) {
                        pipe(upstream, clientOut);
                    } catch (Exception e) {
                        // Best-effort: surface the failure as an SSE error event, mirroring the
                        // frontend's expectation of event/data framing. The 200/headers are already
                        // committed here, so a timeout can't become a 504 on this path.
                        String detail = isTimeout(e)
                                ? "the backend took too long to respond and the stream timed out"
                                : e.getMessage();
                        log.warn("SSE relay interrupted: {}", detail);
                        writeErrorEvent(clientOut, detail);
                    }
                    return null;
                });
    }

    // ---- The problem: blocking baseline ----

    @PostMapping("/chat/sync")
    public ResponseEntity<String> chatSync(@RequestBody ChatRequest request) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return restTemplate.exchange(
                backendBaseUrl + "/api/chat/sync",
                HttpMethod.POST,
                new HttpEntity<>(request, headers),
                String.class);
    }

    // ---- Fix 2: async start + poll ----

    @PostMapping("/chat/async")
    public ResponseEntity<String> startAsync(@RequestBody ChatRequest request) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return restTemplate.exchange(
                backendBaseUrl + "/api/chat/async",
                HttpMethod.POST,
                new HttpEntity<>(request, headers),
                String.class);
    }

    @GetMapping("/jobs/{jobId}")
    public ResponseEntity<String> getJob(@PathVariable String jobId,
                                         @RequestParam(defaultValue = "redis") String store) {
        String url = UriComponentsBuilder.fromHttpUrl(backendBaseUrl)
                .path("/api/jobs/{jobId}")
                .queryParam("store", store)
                .buildAndExpand(jobId)
                .toUriString();
        return restTemplate.exchange(url, HttpMethod.GET, HttpEntity.EMPTY, String.class);
    }

    // ---- Error handling (applies to the non-streaming endpoints; the SSE path surfaces
    //      timeouts as an SSE error event, since its 200 status/headers are already committed) ----

    /** Pass upstream 4xx/5xx status and body straight through to the browser. */
    @ExceptionHandler(HttpStatusCodeException.class)
    public ResponseEntity<String> handleUpstreamStatus(HttpStatusCodeException ex) {
        return ResponseEntity.status(ex.getStatusCode())
                .contentType(MediaType.APPLICATION_JSON)
                .body(ex.getResponseBodyAsString());
    }

    @ExceptionHandler(ResourceAccessException.class)
    public ResponseEntity<String> handleUpstreamFailure(ResourceAccessException ex) {
        HttpStatus status = isTimeout(ex) ? HttpStatus.GATEWAY_TIMEOUT : HttpStatus.BAD_GATEWAY;
        log.warn("Upstream relay failed ({}): {}", status, ex.getMessage());
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_JSON)
                .body("{\"error\":\"backend unavailable\"}");
    }

    private static boolean isTimeout(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause()) {
            if (c instanceof SocketTimeoutException) {
                return true;
            }
        }
        return false;
    }

    /** Copies the upstream stream to the client, flushing each chunk so SSE stays real-time. */
    private static void pipe(InputStream in, OutputStream out) throws Exception {
        byte[] buffer = new byte[512];
        int read;
        while ((read = in.read(buffer)) != -1) {
            out.write(buffer, 0, read);
            out.flush();
        }
    }

    private static void writeErrorEvent(OutputStream out, String message) {
        try {
            String safe = message == null ? "relay error" : message.replaceAll("[\\r\\n]+", " ");
            out.write(("event: error\ndata: " + safe + "\n\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
        } catch (Exception ignored) {
            // client already gone; nothing more to do
        }
    }
}
