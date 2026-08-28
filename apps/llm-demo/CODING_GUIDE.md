# Coding Guide — SSE Streaming

This demo streams LLM tokens from the backend to the browser over **Server-Sent Events (SSE)**. SSE is
the part that's easy to get subtly wrong, so this guide walks the whole path — server → wire → client →
infra — and calls out every gotcha we actually hit. For general architecture see
[`llm-demo-architecture.md`](llm-demo-architecture.md).

---

## The end-to-end path

```
OpenAI  --Flux<String> tokens-->  OpenAiService
                                      │
                                      ▼
ChatController  --Flux<ServerSentEvent<Object>>-->  Spring WebFlux SSE encoder
                                                          │  text/event-stream
                                                          ▼
                        CloudFront (/api/* behavior)  ──►  ALB  ──►  browser
                                                                       │
                                                       fetch + getReader() parses raw SSE
```

Nothing buffers end to end: each token is flushed the moment it arrives.

---

## 1. Server — producing the SSE stream

### `ChatController.java`
```java
@PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<Object>> chat(@RequestBody ChatRequest request) { ... }
```

Three rules, each load-bearing:

1. **`produces = MediaType.TEXT_EVENT_STREAM_VALUE` is mandatory.**
   Without it Spring buffers the *entire* `Flux` and serializes it as one JSON array at the end — the
   stream silently degrades to "everything appears at once." This single annotation is the difference
   between streaming and not.

2. **`Flux.concat(tokenStream, doneEvent)` — never `merge`.**
   `concat` subscribes to `doneEvent` only after `tokenStream` completes, guaranteeing the `[DONE]`
   sentinel is the *last* event. `merge` runs them concurrently and `[DONE]` could arrive before the last
   token.

3. **Tokens are JSON-encoded, not raw strings.** Each token is wrapped in a record:
   ```java
   public record TokenChunk(String content) {}
   ...
   .data(new TokenChunk(token))   // -> data: {"content":"..."}
   ```
   See the wire-format section for *why this is not optional*.

Emitted events:
```
event: token
data: {"content":"Hello"}

event: token
data: {"content":" world"}

event: done
data: [DONE]
```
The `[DONE]` event keeps `.data("[DONE]")` as a **plain String**. Spring's SSE encoder writes String data
literally and only runs non-String data through the JSON encoder — so `TokenChunk` becomes JSON while the
sentinel stays unquoted.

### `OpenAiService.java`
```java
chatClient.prompt().user(userMessage).stream().content();  // Flux<String>, one element per token
```
`.stream()` (not `.call()`) is what puts the provider in streaming mode. `.content()` gives a cold
`Flux<String>` of token chunks; the controller maps each to a `ServerSentEvent`. The stream is **cold** —
work starts per subscriber, i.e. per HTTP request. Don't cache or share it.

---

## 2. The wire format — the #1 gotcha ⚠️

**Why tokens are JSON-encoded instead of sent as raw text.** The SSE text protocol mangles raw token text
in two ways:

- **Leading spaces vanish.** SSE strips one optional space after `data:`. LLM tokens often *are* a leading
  space (`" world"`), and Spring writes `data:<token>` with no space of its own — so the client's
  spec-compliant "strip one leading space" eats the token's own space. Result: `Helloworld`.
- **Newlines vanish.** A token containing `\n` is split by SSE framing into multiple `data:` lines for one
  event; a naive client drops all but the first. Result: no line breaks.

JSON is immune to both: `{"content":" world"}` has no leading space to strip, and `\n` is escaped to the
two characters `\n` inside a single line. **If you ever change the server back to raw-string `data:`, you
reintroduce both bugs.** The two sides are a contract — change one, change the other:

| Server (`ChatController`)      | Client (`index.html`)              |
| ------------------------------ | ---------------------------------- |
| `data: {"content":"..."}`      | `JSON.parse(data).content`         |

---

## 3. Client — parsing the SSE stream

### `apps/llm-demo/frontend/index.html`

- **Uses `fetch` + `response.body.getReader()`, NOT `EventSource`.**
  `EventSource` only does GET; `/api/chat` is POST (it carries the prompt in the body). Do not "simplify"
  to `EventSource` — it cannot send this request at all.

- **Manual line framing.** The reader yields arbitrary byte chunks, so the code buffers and splits on
  `\n`, tracks the current `event:` type, and processes `data:` lines. Key steps:
  ```
  buffer += decoder.decode(value, { stream: true });   // TextDecoder streaming mode
  split complete lines on '\n', keep the trailing partial line buffered
  line 'event:x'  -> remember eventType
  line 'data:y'   -> if eventType==='token': text = JSON.parse(y).content; append
                     if eventType==='done' : stop, record metrics
  ```
  Two easy-to-break details:
  - `TextDecoder({ stream: true })` — a multi-byte UTF-8 char can straddle two chunks; streaming mode
    holds the partial byte until the rest arrives. Don't decode chunks independently.
  - Only append `data:` when the current `eventType === 'token'`, and reset `eventType` after each `data:`
    line.

- **`JSON.parse(data).content`** with a raw-string fallback — the client half of the wire contract.

- **Newlines only render because `.output` has `white-space: pre-wrap`** in the CSS. If you drop that,
  streamed line breaks collapse even though the data is correct.

### Local dev caveat
`const API_URL = '/api/chat'` is **relative** (so it works behind CloudFront with no CORS). For a
pure-local backend you must temporarily point it at `http://localhost:8080/api/chat` — and **not commit
that**.

---

## 4. Infra — keeping the stream alive

SSE holds one HTTP connection open for the whole response, so the network path must not buffer or time it
out. The pieces that specifically matter for streaming:

- **ALB `idle_timeout = 300`** (`alb.tf`). The default 60s can drop a connection that's slow to produce its
  first token. Raise this, not lower it.
- **CloudFront `/api/*` behavior** (`s3_cloudfront.tf`):
  - **caching disabled** — a cached response would defeat streaming entirely.
  - **AllViewer origin-request policy** + **all methods incl. POST** — the prompt is a POST body.
  - **`origin_read_timeout = 60`** — CloudFront's max without a service-quota increase. It caps how long
    CloudFront waits for the first bytes from the origin; fine for typical first-token latency, but very
    slow first tokens can truncate. This is the usual suspect if "the stream cuts off around ~60s."
- The default S3 origin serves the static page; only `/api/*` is the streaming path.

---

## Symptom → cause quick reference

| Symptom                                   | Cause                                                                 |
| ----------------------------------------- | --------------------------------------------------------------------- |
| All text appears at once at the end       | Missing `produces = TEXT_EVENT_STREAM_VALUE` on the controller        |
| `[DONE]` arrives before the last token    | Used `Flux.merge` instead of `Flux.concat`                            |
| Words run together (`Helloworld`)         | Reverted to raw-string `data:`; leading space stripped by SSE         |
| No line breaks in output                  | Raw-string `data:` (newlines lost) **or** missing `white-space: pre-wrap` |
| Garbled multi-byte characters             | Decoding chunks without `TextDecoder({ stream: true })`               |
| 405 on `/api/chat` from the browser bar   | It's POST-only; a browser GET can't drive it — use the frontend/curl  |
| Stream truncates around ~60s              | CloudFront `origin_read_timeout` cap (raise the quota) / ALB idle timeout |
| Frontend can't reach API locally          | Relative `API_URL` not pointed at `localhost:8080` for local runs     |
