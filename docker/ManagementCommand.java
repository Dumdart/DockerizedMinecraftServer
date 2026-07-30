import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeUnit;

public final class ManagementCommand {
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(10);
    private static final Duration RESPONSE_TIMEOUT = Duration.ofMinutes(2);

    private ManagementCommand() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            throw new IllegalArgumentException(
                    "usage: ManagementCommand URI SECRET_FILE METHOD PARAMS_JSON");
        }

        URI endpoint = URI.create(args[0]);
        String secret = Files.readString(Path.of(args[1])).trim();
        String method = args[2];
        String params = args[3];

        if (!endpoint.getScheme().equals("ws") && !endpoint.getScheme().equals("wss")) {
            throw new IllegalArgumentException("management URI must use ws or wss");
        }
        if (!secret.matches("[A-Za-z0-9]{40}")) {
            throw new IllegalArgumentException("management secret must be 40 alphanumeric characters");
        }
        if (!method.matches("(rpc|minecraft):[A-Za-z0-9_./-]+") && !method.equals("rpc.discover")) {
            throw new IllegalArgumentException("invalid management method: " + method);
        }
        boolean arrayParams = params.startsWith("[") && params.endsWith("]");
        boolean objectParams = params.startsWith("{") && params.endsWith("}");
        if (!arrayParams && !objectParams) {
            throw new IllegalArgumentException("params must be a JSON array or object");
        }

        String request = """
                {"jsonrpc":"2.0","id":1,"method":"%s","params":%s}
                """.formatted(method, params).strip();
        ResponseListener listener = new ResponseListener();

        try (HttpClient client = HttpClient.newBuilder()
                .connectTimeout(CONNECT_TIMEOUT)
                .build()) {
            WebSocket socket = client.newWebSocketBuilder()
                    .connectTimeout(CONNECT_TIMEOUT)
                    .header("Authorization", "Bearer " + secret)
                    .buildAsync(endpoint, listener)
                    .get(CONNECT_TIMEOUT.toSeconds(), TimeUnit.SECONDS);

            socket.sendText(request, true).get(CONNECT_TIMEOUT.toSeconds(), TimeUnit.SECONDS);
            String response = listener.response()
                    .get(RESPONSE_TIMEOUT.toSeconds(), TimeUnit.SECONDS);
            socket.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();

            System.out.println(response);
            int resultIndex = response.indexOf("\"result\"");
            int errorIndex = response.indexOf("\"error\"");
            boolean topLevelError = errorIndex >= 0
                    && (resultIndex < 0 || errorIndex < resultIndex);
            boolean wrappedError = response.matches(
                    "(?s).*\"result\"\\s*:\\s*\\{\\s*\"jsonrpc\"\\s*:\\s*\"2.0\""
                            + "\\s*,\\s*\"id\"\\s*:\\s*1\\s*,\\s*\"error\"\\s*:.*");
            if (topLevelError || wrappedError) {
                System.exit(2);
            }
        }
    }

    static final class ResponseListener implements WebSocket.Listener {
        private final CompletableFuture<String> response = new CompletableFuture<>();
        private final StringBuilder message = new StringBuilder();

        CompletableFuture<String> response() {
            return response;
        }

        @Override
        public void onOpen(WebSocket webSocket) {
            webSocket.request(1);
        }

        @Override
        public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
            message.append(data);
            if (last) {
                String completeMessage = message.toString();
                message.setLength(0);

                // Check notifications are skipped until the response to request id 1 arrives.
                if (completeMessage.matches("(?s).*\"id\"\\s*:\\s*1(?:\\D|$).*")) {
                    response.complete(completeMessage);
                }
            }
            webSocket.request(1);
            return null;
        }

        @Override
        public void onError(WebSocket webSocket, Throwable error) {
            response.completeExceptionally(error);
        }
    }
}
