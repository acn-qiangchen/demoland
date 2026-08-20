package com.demo.llm;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Lightweight liveness probe for the ALB target-group health check (see app.json healthEndpoint). */
@RestController
public class HealthController {

    @GetMapping("/health")
    public String health() {
        return "ok";
    }
}
