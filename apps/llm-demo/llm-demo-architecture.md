# LLM Streaming Demo — Architecture & Reconstruction Spec

> **Purpose of this document**
> This is a self-contained specification. An AI agent reading this file should be able to reproduce the entire working demo from scratch without any other context.

---

## 1. What the Demo Does

A single-page web UI lets a user type a prompt. The browser POSTs to a Spring Boot backend, which calls the OpenAI API with streaming enabled. The backend pipes each token back to the browser as a Server-Sent Event (SSE). Tokens appear in the UI in real time — character by character — as OpenAI generates them. A metrics strip shows time-to-first-byte, total time, and token count.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Browser  (index.html — vanilla JS)                         │
│                                                             │
│  fetch POST /api/chat  { "message": "..." }                 │
│  ReadableStream reader — parses raw SSE lines               │
│  Appends tokens to DOM as they arrive                       │
└──────────────────────┬──────────────────────────────────────┘
                       │  HTTP  text/event-stream
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Spring Boot 3.4  (WebFlux — reactive, non-blocking)        │
│                                                             │
│  ChatController   POST /api/chat                            │
│    └─ OpenAiService                                      │
│         └─ Spring AI ChatClient  .stream().content()        │
│              └─ Flux<String>  (one element = one token)     │
│                                                             │
│  Maps Flux<String> → Flux<ServerSentEvent<String>>          │
│  Appends a final  event:done / data:[DONE]  sentinel        │
└──────────────────────┬──────────────────────────────────────┘
                       │  HTTPS  stream:true
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  OpenAI API                                              │
│  Model: gpt-4o                                   │
│  Streaming: true  →  chat-completion delta SSE events                  │
│  (Spring AI handles wire-protocol parsing internally)       │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Technology Stack

| Layer | Technology | Version | Reason |
|---|---|---|---|
| Backend framework | Spring Boot | 3.4.x | WebFlux reactive stack, Java 17+ |
| Reactive runtime | Spring WebFlux | (bundled) | Native SSE via `Flux<ServerSentEvent>` |
| LLM abstraction | Spring AI | 1.0.0 | Hides OpenAI wire-protocol, 3-line streaming |
| LLM provider | Spring AI OpenAI starter | 1.0.0 | Auto-configures `ChatClient` |
| HTTP client | WebClient | (bundled) | Non-blocking, used internally by Spring AI |
| Build tool | Maven | 3.x | Standard Spring Boot toolchain |
| Java version | Java 17 | 17+ | Required by Spring Boot 3.x |
| Frontend | Vanilla JS + HTML | — | No build step; open directly in browser |
| LLM model | gpt-4o | — | OpenAI, streaming-capable |

---

## 4. Project Structure

```
llm-demo/
├── backend/
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/demo/llm/
│       │   ├── LlmDemoApplication.java     ← @SpringBootApplication entry point
│       │   ├── ChatRequest.java            ← record DTO  { String message }
│       │   ├── OpenAiService.java       ← Spring AI ChatClient wrapper
│       │   └── ChatController.java         ← POST /api/chat → SSE stream
│       └── resources/
│           └── application.properties      ← API key, model, timeout config
└── frontend/
    └── index.html                          ← entire UI in one file, no build needed
```

---

## 5. Maven Dependencies (`pom.xml`)

**Parent:**
```xml
<parent>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-parent</artifactId>
  <version>3.4.1</version>
</parent>
```

**BOM (import in `<dependencyManagement>`):**
```xml
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-bom</artifactId>
  <version>1.0.0</version>
  <type>pom</type>
  <scope>import</scope>
</dependency>
```

**Runtime dependencies:**
```xml
<!-- Reactive web + SSE -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-webflux</artifactId>
</dependency>

<!-- Spring AI OpenAI provider (brings in ChatClient auto-config) -->
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-starter-model-openai</artifactId>
</dependency>
```

**Repository** (required for Spring AI milestone builds):
```xml
<repository>
  <id>spring-milestones</id>
  <url>https://repo.spring.io/milestone</url>
</repository>
```

---

## 6. Configuration (`application.properties`)

```properties
# API key — inject via environment variable, never hardcode
spring.ai.openai.api-key=${SPRING_AI_OPENAI_API_KEY:your-api-key-here}
spring.ai.openai.chat.options.model=gpt-4o
spring.ai.openai.chat.options.max-tokens=2048

# How long Spring AI's WebClient will wait for OpenAI (covers slow first-token)
app.webclient.response-timeout-seconds=120

server.port=8080

# Open CORS for local demo; restrict in production
app.cors.allowed-origins=*
```

---

## 7. Backend — Java Files

### 7.1 `LlmDemoApplication.java`
Standard Spring Boot entry point. No customisation needed.

```java
@SpringBootApplication
public class LlmDemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(LlmDemoApplication.class, args);
    }
}
```

---

### 7.2 `ChatRequest.java`
Simple record DTO matching the JSON body sent by the browser.

```java
public record ChatRequest(String message) {}
```

---

### 7.3 `OpenAiService.java`
Wraps Spring AI's `ChatClient`. Returns a cold `Flux<String>` where each element is one text token from OpenAI. Spring AI internally handles:
- Building the OpenAI JSON request (`model`, `messages`, `stream: true`, `max_tokens`)
- Parsing `chat-completion delta` SSE events from OpenAI
- Surfacing only the token text strings

```java
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
                .stream()       // switches to streaming mode
                .content();     // Flux<String> of token chunks
    }
}
```

---

### 7.4 `ChatController.java`
Exposes `POST /api/chat`. Returns `text/event-stream`.

SSE event format emitted to the browser. Each token is **JSON-encoded** in the `data:` field
(`{"content":"..."}`) so leading spaces and newlines survive the SSE text protocol:
```
event: token
data: {"content":"Hello"}

event: token
data: {"content":" world"}

...

event: done
data: [DONE]
```

```java
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class ChatController {

    private final OpenAiService openAiService;

    public ChatController(OpenAiService openAiService) {
        this.openAiService = openAiService;
    }

    // JSON-encoded so token whitespace/newlines survive the SSE text protocol.
    public record TokenChunk(String content) {}

    @PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<Object>> chat(@RequestBody ChatRequest request) {

        Flux<ServerSentEvent<Object>> tokenStream = openAiService
                .streamResponse(request.message())
                .map(token -> ServerSentEvent.<Object>builder()
                        .event("token")
                        .data(new TokenChunk(token)) // -> data: {"content":"..."}
                        .build());

        Flux<ServerSentEvent<Object>> doneEvent = Flux.just(
                ServerSentEvent.<Object>builder()
                        .event("done")
                        .data("[DONE]")
                        .build());

        return Flux.concat(tokenStream, doneEvent);
    }
}
```

**Key decisions:**
- `produces = MediaType.TEXT_EVENT_STREAM_VALUE` tells Spring to keep the HTTP connection open and flush each element immediately
- `Flux.concat(tokenStream, doneEvent)` guarantees the `[DONE]` sentinel arrives after all tokens
- **Tokens are JSON-encoded** (`TokenChunk` record → `{"content":"..."}`). Sending the raw string breaks on the SSE text protocol: `data:` strips one leading space (dropping inter-word spaces) and splits embedded newlines across multiple `data:` lines (dropping line breaks). Spring writes non-String data via its JSON encoder while a plain String like `"[DONE]"` is written literally, so the `done` sentinel stays unquoted.
- `@CrossOrigin("*")` is required because `index.html` is opened from `file://` or a different port

---

## 8. Frontend (`index.html`)

Single HTML file. No npm, no build step. Open directly in any browser.

### 8.1 Visual design tokens
```
Background:   #0d0f12   (near-black)
Surface:      #151820
Border:       #252a35
Accent:       #4f8ef7   (blue)
Text:         #c9d1e0
Text bright:  #eaf0ff
Green:        #3dd68c   (status active)
Red:          #f87171   (error)
Fonts:        IBM Plex Mono (terminal output, labels, button)
              IBM Plex Sans (subtitle, body)
```

### 8.2 UI elements
- **Terminal window** — monospaced output area styled like a macOS terminal, with three dot decorations in the title bar
- **Blinking cursor** — CSS animated `<span>` injected before each token, removed and re-appended as tokens arrive
- **Metrics strip** — shows time-to-first-byte (ms), total time (s), token count; hidden until first response
- **Input area** — `>_` prompt prefix, `<textarea>`, Enter to submit / Shift+Enter for newline
- **Status indicator** — small dot + label (ready / connecting… / streaming… / done / error)
- **Footer tags** — stack labels (Spring Boot 3.4, Spring AI 1.0, WebFlux SSE, gpt-4o, Vanilla JS)

### 8.3 SSE parsing logic (vanilla JS)

The browser uses `fetch` + `response.body.getReader()` — **not** the `EventSource` API — because `EventSource` does not support POST requests.

```
Algorithm:
1. POST { message } to /api/chat
2. Get ReadableStream from response.body
3. Decode chunks with TextDecoder({ stream: true })
4. Buffer incomplete lines; split on '\n'
5. Track current eventType from lines starting with 'event:'
6. On lines starting with 'data:':
     if eventType === 'token' → JSON.parse(data).content, append text node to output, update metrics
     if eventType === 'done'  → remove cursor, record total time
7. Reset eventType after each data: line
```

The blinking cursor `<span>` is removed before each token append and re-added after, so it always stays at the end of the text.

### 8.4 API call
```javascript
const response = await fetch('http://localhost:8080/api/chat', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ message })
});
// Then read response.body as a ReadableStream (see 8.3)
```

---

## 9. How to Run Locally

```bash
# Step 1 — start the backend
cd llm-demo/backend
export SPRING_AI_OPENAI_API_KEY=sk-...
mvn spring-boot:run

# Step 2 — open the frontend (no server needed)
open llm-demo/frontend/index.html
# or double-click the file in your OS file manager
```

Backend starts on `http://localhost:8080`. The frontend hardcodes `API_URL = 'http://localhost:8080/api/chat'` — change this constant if the backend port differs.

---

## 10. AWS Deployment Considerations

### ALB (recommended for this stack)
| Setting | Recommendation |
|---|---|
| Idle timeout | Increase from 60s to **120–300s** |
| Why | SSE keeps the connection alive per token, but if first-token latency exceeds idle timeout, ALB drops the connection. Tune to your observed p99 first-token latency + buffer. |

### API Gateway
As of late 2025, API Gateway REST APIs support response streaming with up to **15-minute timeout** and native SSE, replacing the old hard 29-second limit. Key constraints:
- Only works with `HTTP_PROXY` or `AWS_PROXY` integration types
- Must set response transfer mode to `STREAM` (default is `BUFFERED`)
- Streaming is REST API only — HTTP API (v2) still has the 29s limit
- Idle timeout: 5 minutes for Regional/private endpoints; 30 seconds for edge-optimized
- Streaming is best suited to Lambda backends; direct HTTP proxy to Spring Boot behaves differently

**Simplest path:** Put Spring Boot behind **ALB only**, bump idle timeout. Avoid API Gateway for the `/api/chat` streaming endpoint unless Lambda is in the path.

---

## 11. Constraints & Notes for the Reproducing Agent

1. **Do not use `EventSource`** for the SSE client — it only supports GET. Use `fetch` + `ReadableStream`.
2. **Spring AI version must be `1.0.0`** (or later). Earlier milestones have different artifact IDs.
3. **The Spring Milestones repository must be declared** in `pom.xml` or Maven will not resolve Spring AI artifacts.
4. **API key must never appear in frontend code.** It lives in `application.properties` and is injected via environment variable.
5. **`@CrossOrigin("*")`** on the controller is required for `file://` → `localhost` requests. In production, restrict to your actual origin.
6. **`Flux.concat(tokenStream, doneEvent)`** — the `done` sentinel must come after all tokens, not in parallel. Use `concat`, not `merge`.
7. **`produces = MediaType.TEXT_EVENT_STREAM_VALUE`** is mandatory on the controller method. Without it, Spring buffers the entire response before sending.
8. The frontend `API_URL` constant must match the backend host/port. Update it if deploying to a non-localhost address.
