package com.demo.llm;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Wraps Spring AI's {@link ChatClient}. Returns a cold {@code Flux<String>} where each element is one
 * text token from OpenAI. Spring AI internally builds the OpenAI streaming request, parses the
 * chat-completion delta events, and surfaces only the token text strings.
 */
@Service
public class OpenAiService {

    private final ChatClient chatClient;

    public OpenAiService(ChatClient.Builder builder) {
        this.chatClient = builder
                .defaultSystem("You are a helpful assistant. Be concise and clear.")
                .build();
    }

    public Flux<String> streamResponse(String userMessage) {
        return chatClient
                .prompt()
                .user(userMessage)
                .stream()   // switches to streaming mode
                .content(); // Flux<String> of token chunks
    }

    /**
     * Collects the full OpenAI token stream server-side and returns a single concatenated string.
     * The browser receives one JSON payload only after generation completes — no streaming to client.
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
