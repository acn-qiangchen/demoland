package com.demo.async;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

/**
 * Wraps Spring AI's {@link ChatClient}. Collects the full OpenAI response server-side and returns it
 * as a single string. Unlike the SSE demo, nothing is streamed to the caller — the result is stashed
 * in a job store and retrieved later via polling.
 */
@Service
public class OpenAiService {

    private final ChatClient chatClient;

    public OpenAiService(ChatClient.Builder builder) {
        this.chatClient = builder
                .defaultSystem("You are a helpful assistant. Be concise and clear.")
                .build();
    }

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
