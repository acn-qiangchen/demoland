package com.demo.bff;

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
import org.springframework.web.util.UriComponentsBuilder;

import java.net.SocketTimeoutException;

/**
 * BFF relay for the async demo. Both endpoints mirror the backend contract so the frontend needs no
 * path changes — only its origin points here.
 *
 * <ul>
 *   <li>{@code POST /api/chat/async} → forwards the start request, returns the backend's job id (202).</li>
 *   <li>{@code GET /api/jobs/{jobId}?store=…} → forwards the poll request, returns the job state.</li>
 * </ul>
 *
 * Upstream responses (including non-2xx status and JSON body) are passed through unchanged so the
 * browser sees the backend's real status codes (202 / 200 / 404 / 400).
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class RelayController {

    private static final Logger log = LoggerFactory.getLogger(RelayController.class);

    private final RestTemplate restTemplate;
    private final String backendBaseUrl;

    public RelayController(RestTemplate llmRestTemplate, LlmClientProperties props) {
        this.restTemplate = llmRestTemplate;
        this.backendBaseUrl = props.getService().getBaseUrl();
    }

    @PostMapping("/chat/async")
    public ResponseEntity<String> startAsync(@RequestBody AsyncChatRequest request) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return restTemplate.exchange(
                backendBaseUrl + "/api/chat/async",
                HttpMethod.POST,
                new HttpEntity<>(request, headers),
                String.class);
    }

    @PostMapping("/chat/sync")
    public ResponseEntity<String> chatSync(@RequestBody AsyncChatRequest request) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return restTemplate.exchange(
                backendBaseUrl + "/api/chat/sync",
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
}
