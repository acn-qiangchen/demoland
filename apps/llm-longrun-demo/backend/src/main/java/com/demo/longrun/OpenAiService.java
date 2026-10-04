package com.demo.longrun;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Wraps Spring AI's {@link ChatClient}. Exposes the same underlying OpenAI call two ways:
 *
 * <ul>
 *   <li>{@link #streamResponse(String)} — a cold {@code Flux<String>} where each element is one text
 *       token, used by the SSE path so the browser sees tokens as they generate.</li>
 *   <li>{@link #getFullResponse(String)} — collects the whole token stream server-side and returns a
 *       single concatenated string, used by both the blocking sync baseline and the async job runner
 *       (nothing is streamed to the caller; the result is returned/stashed once generation finishes).</li>
 * </ul>
 */
@Service
public class OpenAiService {

    private final ChatClient chatClient;

    public OpenAiService(ChatClient.Builder builder) {
        this.chatClient = builder
                .defaultSystem("You are a helpful assistant. Be concise and clear.")
                .build();
    }

    /** Streaming mode: a {@code Flux<String>} of token chunks surfaced as they arrive. */
    public Flux<String> streamResponse(String userMessage) {
        return chatClient
                .prompt()
                .user(userMessage)
                .stream()   // switches to streaming mode
                .content(); // Flux<String> of token chunks
    }

    /**
     * Collects the full OpenAI token stream server-side and returns a single concatenated string.
     * The caller receives one payload only after generation completes — no streaming to client.
     */
    public Mono<String> getFullResponse(String userMessage) {
        return chatClient
                .prompt()
                .user(userMessage)
                .stream()
                .content()
                .collectList()
                .map(chunks -> String.join("", chunks));
    }
}
