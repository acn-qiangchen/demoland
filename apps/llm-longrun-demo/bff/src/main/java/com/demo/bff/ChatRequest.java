package com.demo.bff;

/** JSON body received from the browser and forwarded verbatim to the backend: { "message", "store" }. */
public record ChatRequest(String message, String store) {}
