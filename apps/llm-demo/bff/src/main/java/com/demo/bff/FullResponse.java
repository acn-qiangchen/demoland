package com.demo.bff;

/** JSON payload returned by the backend's blocking endpoint, relayed unchanged to the browser. */
public record FullResponse(String content) {}
