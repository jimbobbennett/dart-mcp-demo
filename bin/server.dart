import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:dart_pieces_mcp/json_rpc_handler.dart';

void main() async {
  // Store all active SSE connections
  final connections = <StreamController<List<int>>>[];
  
  // Create an instance of JsonRpcHandler
  final jsonRpcHandler = JsonRpcHandler();

  // Helper to send a message to all the connected clients. All messages go to all clients.
  // There's probably a smarter way to do this, but this works for now.
  //
  // The message is JsonRPC as a string, and gets encoded as an SSE message here
  sendMessageOverSSE(String message) {
    print('Broadcasting to ${connections.length} clients');
    print('message: $message');

    // Loop through all the connections
    for (var controller in List.from(connections)) {
      try {
        // If the client is not closed, we send the message.
        // The message is sent as a SSE message event, all encoded as UTF-8
        if (!controller.isClosed) {
          controller.add(utf8.encode('event: message\ndata: $message\n\n'));
          print('Message sent');
        }
      } catch (e) {
        // Clean up failed connections
        if (connections.contains(controller)) {
          connections.remove(controller);
          controller.close();
        }
      }
    }
  }

  // Handle messages sent to the /message endpoint
  // These are JsonRPC, and routed to a handler that generates a response based on the message method. This
  // response is then sent back to the client over the open SSE connections.
  Response processMessage(String body) {
    try {
      final jsonRpcMessage = JsonRpcMessage.fromJson(json.decode(body));
      print('Message: $jsonRpcMessage');

      // Build the JsonRPC response
      final responseMessage = jsonRpcHandler.getResponseForRequest(jsonRpcMessage);

      // Send the response over SSE
      sendMessageOverSSE(responseMessage);

      // Always return 200 unless we have an exception - the response goes over SSE
      return Response.ok('Message sent');
    } catch (e) {
      print('Error processing JSON-RPC: $e');
      return Response(400,
          body: json.encode({
            'jsonrpc': '2.0',
            'error': {'code': -32700, 'message': 'Parse error'},
            'id': null
          }),
          headers: {'Content-Type': 'application/json'});
    }
  }

  // Handle the messages sent to the server
  // This handles 2 endpoints:
  // - /sse: This is the endpoint for the SSE connection
  // - /message: This is the endpoint for the JSON-RPC messages
  //
  // When a client connects over /sse, we store the connection and return an SSE message with the endpoint info
  // to post messages to.
  // When we get a message on /message, we process the JSON-RPC message and send a response back over the open SSE connections. The /message
  // endpoint will then return 200.
  // See the MCP spec: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/#http-with-sse
  handler(Request request) {
    print('Request: ${request.method} ${request.url}');

    // SSE messages - open a stream and keep it open
    if (request.url.path == 'sse') {
      print('Client connecting...');

      // Create a new controller for this connection
      final controller = StreamController<List<int>>();
      controller.onCancel = () {
        print('Client disconnected');
        connections.remove(controller);
      };
      connections.add(controller);

      // Initialize the connection with endpoint info
      controller.add(utf8.encode('event: endpoint\ndata: /message\n\n'));

      return Response.ok(controller.stream,
          headers: {'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive'},
          // This seems to be the magic for streaming - without it everything fails. See https://github.com/dart-lang/shelf/issues/54#issuecomment-160045272
          context: {'shelf.io.buffer_output': false}); 
    } else if (request.url.path == 'message' && request.method == 'POST') {
      print('Received message...');

      // Read the message body, then process it, sending the response over SSE
      request.readAsString().then((body) {
        return processMessage(body);
      });

      return Response.ok('Message received');
    }

    // Any other endpoint is a 404
    return Response.notFound('Not Found');
  }

  // Start the server listening on 8080
  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('Server listening on http://${server.address.host}:${server.port}');
}
