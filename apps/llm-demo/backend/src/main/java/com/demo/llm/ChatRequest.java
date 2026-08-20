package com.demo.llm;

/** JSON body sent by the browser: { "message": "..." } */
public record ChatRequest(String message) {}
