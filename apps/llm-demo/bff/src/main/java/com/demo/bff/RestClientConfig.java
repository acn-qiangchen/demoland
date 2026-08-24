package com.demo.bff;

import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.core5.util.Timeout;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

/**
 * Wires a {@link RestTemplate} backed by Apache HttpClient 5 so we get real, tunable timeouts and a
 * connection pool. Timeout values come from {@code llm.http.*} in application.yaml.
 *
 * <p>The response body is streamed (not buffered), which is what lets the SSE relay forward tokens
 * to the browser as they arrive rather than collecting the whole response first.
 */
@Configuration
public class RestClientConfig {

    @Bean
    public RestTemplate llmRestTemplate(LlmClientProperties props) {
        LlmClientProperties.Http http = props.getHttp();

        // connectTimeout lives on the connection config (HttpClient 5 moved it off RequestConfig).
        ConnectionConfig connectionConfig = ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofMilliseconds(http.getConnectTimeout()))
                .build();

        PoolingHttpClientConnectionManager connectionManager =
                PoolingHttpClientConnectionManagerBuilder.create()
                        .setDefaultConnectionConfig(connectionConfig)
                        .build();

        RequestConfig requestConfig = RequestConfig.custom()
                // wait for a pooled connection
                .setConnectionRequestTimeout(Timeout.ofMilliseconds(http.getConnectionRequestTimeout()))
                // socket read timeout — the "request timeout" operators tune
                .setResponseTimeout(Timeout.ofMilliseconds(http.getReadTimeout()))
                .build();

        CloseableHttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .setDefaultRequestConfig(requestConfig)
                .build();

        return new RestTemplate(new HttpComponentsClientHttpRequestFactory(httpClient));
    }
}
