package com.demo.bff;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * BFF relay: the web frontend now talks to this service instead of the LLM backend directly. Both
 * endpoints mirror the backend's contract so the frontend needs no path changes — only its origin
 * points here.
 *
 * <ul>
 *   <li>{@code POST /api/chat}      → streams the backend's {@code text/event-stream} through untouched.</li>
 *   <li>{@code POST /api/chat/rest} → forwards the blocking JSON call and returns the full payload.</li>
 * </ul>
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
                org.springframework.http.HttpMethod.POST,
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

    /** Forwards the blocking call; the browser gets one JSON payload once generation completes. */
    @PostMapping("/chat/rest")
    public FullResponse chatRest(@RequestBody ChatRequest request) {
        return restTemplate.postForObject(
                backendBaseUrl + "/api/chat/rest", request, FullResponse.class);
    }

    /**
     * Maps an upstream read/connect timeout to a 504 Gateway Timeout with a user-facing message.
     * RestTemplate wraps the Apache HttpClient {@link SocketTimeoutException} in a
     * {@link ResourceAccessException}; only the timeout case becomes a 504, other connectivity
     * failures fall through to a 502. This handler applies to the blocking {@code /chat/rest} path
     * (the streaming path surfaces timeouts as an SSE error event, since its 200 status and headers
     * are already committed by the time bytes start flowing).
     */
    @ExceptionHandler(ResourceAccessException.class)
    public ResponseEntity<FullResponse> handleUpstreamFailure(ResourceAccessException ex) {
        if (isTimeout(ex)) {
            log.warn("Upstream timed out: {}", ex.getMessage());
            return ResponseEntity.status(HttpStatus.GATEWAY_TIMEOUT)
                    .body(new FullResponse("The backend took too long to respond and the request timed out. Please try again."));
        }
        log.warn("Upstream unreachable: {}", ex.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(new FullResponse("The backend service is currently unavailable. Please try again."));
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
