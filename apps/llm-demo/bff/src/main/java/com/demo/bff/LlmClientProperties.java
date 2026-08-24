package com.demo.bff;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Binds the {@code llm.*} keys from application.yaml. Groups the upstream LLM service location
 * ({@code llm.service.base-url}) and the HTTP client timeouts ({@code llm.http.*}) that back the
 * RestTemplate / Apache HttpClient instance used to relay calls to the backend.
 */
@ConfigurationProperties(prefix = "llm")
public class LlmClientProperties {

    private final Service service = new Service();
    private final Http http = new Http();

    public Service getService() {
        return service;
    }

    public Http getHttp() {
        return http;
    }

    /** Where the BFF forwards requests — the LLM backend's base URL. */
    public static class Service {
        /** e.g. http://localhost:8080 (or the backend's service DNS in ECS). */
        private String baseUrl;

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }
    }

    /** Apache HttpClient timeouts, all in milliseconds. Tune these per environment. */
    public static class Http {
        /** Max time to establish the TCP connection to the backend. */
        private int connectTimeout;

        /**
         * Max time to wait for data on the socket (the "request timeout" the operator tunes).
         * For the SSE relay this is the gap allowed *between* token chunks, not the total stream
         * duration — set it comfortably above the model's inter-token latency.
         */
        private int readTimeout;

        /** Max time to wait for a free connection from the pool. */
        private int connectionRequestTimeout;

        public int getConnectTimeout() {
            return connectTimeout;
        }

        public void setConnectTimeout(int connectTimeout) {
            this.connectTimeout = connectTimeout;
        }

        public int getReadTimeout() {
            return readTimeout;
        }

        public void setReadTimeout(int readTimeout) {
            this.readTimeout = readTimeout;
        }

        public int getConnectionRequestTimeout() {
            return connectionRequestTimeout;
        }

        public void setConnectionRequestTimeout(int connectionRequestTimeout) {
            this.connectionRequestTimeout = connectionRequestTimeout;
        }
    }
}
