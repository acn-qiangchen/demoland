package com.demo.async;

/**
 * JSON body sent by the browser to kick off a job: { "message": "...", "store": "redis" | "dynamo" }.
 * {@code store} selects which backing store this job is written to and later polled from; it defaults
 * to redis when omitted.
 */
public record AsyncChatRequest(String message, String store) {}
