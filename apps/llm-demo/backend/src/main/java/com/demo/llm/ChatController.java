package com.demo.llm;

import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class ChatController {

    private final OpenAiService openAiService;

    public ChatController(OpenAiService openAiService) {
        this.openAiService = openAiService;
    }

    /**
     * Token payload sent as the SSE {@code data:} field. Encoding the token as JSON (rather than the
     * raw string) is deliberate: the SSE text protocol strips a single leading space after {@code data:}
     * and splits embedded newlines across multiple {@code data:} lines, which would silently drop
     * inter-word spaces and line breaks. JSON preserves both exactly.
     */
    public record TokenChunk(String content) {
    }

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
}
