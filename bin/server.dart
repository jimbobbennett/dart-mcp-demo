import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() async {
  // Store all active SSE connections
  final connections = <StreamController<List<int>>>[];

  String initialize(id) {
    return json.encode({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'logging': {},
          'prompts': {},
          'resources': {},
          'tools': {'ask_pieces_ltm': true},
        },
        'serverInfo': {'name': 'PiecesMCP', 'version': '1.0.0'}
      },
      'id': id
    });
  }

  String listTools(id) {
    return json.encode({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {
        'tools': [
          {
            'name': 'ask_pieces_ltm',
            'description': 'Ask the Pieces LTM a question',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'question': {'type': 'string', 'description': 'The question to ask the Pieces LTM'}
              },
              'required': ['question']
            }
          }
        ]
      }
    });
  }

  String callTool(id, tool, arguments) {
    return json.encode({
      'jsonrpc': '2.0',
      'id': 2,
      'result': {
        'content': [
          {'type': 'text', 'text': 'Current weather in New York:\nTemperature: 72°F\nConditions: Partly cloudy'}
        ],
        'isError': false
      }
    });
  }

  sendMessage(String message) {
    print('Broadcasting to ${connections.length} clients');
    print('message: $message');
    for (var controller in List.from(connections)) {
      try {
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

  Response processMessage(String body) {
    Map<String, dynamic> jsonRpc;
    try {
      jsonRpc = json.decode(body);
      print('Received JSON-RPC: $jsonRpc');

      // Validate JSON-RPC format
      if (!jsonRpc.containsKey('jsonrpc') || jsonRpc['jsonrpc'] != '2.0' || !jsonRpc.containsKey('method')) {
        return Response(400,
            body: json.encode({
              'jsonrpc': '2.0',
              'error': {'code': -32600, 'message': 'Invalid Request'},
              'id': jsonRpc.containsKey('id') ? jsonRpc['id'] : null
            }),
            headers: {'Content-Type': 'application/json'});
      }

      // Process the method call
      final method = jsonRpc['method'];
      final params = jsonRpc['params'];
      final id = jsonRpc['id'];

      print('Method: $method, Params: $params, ID: $id');

      if (method == 'initialize') {
        print('initialize');
        sendMessage(initialize(id));
      } else if (method == 'tools/list') {
        print('tools/list');
        sendMessage(listTools(id));
      } else if (method == 'tools/call') {
        print('tools/call');
        sendMessage(callTool(id, params['name'], params['arguments']));
      } else if (method == 'ping') {
        print('ping');
        sendMessage(json.encode({'jsonrpc': '2.0', 'id': id, 'method': 'ping'}));
      }

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

  // Middleware to handle /sse endpoint
  handler(Request request) {
    print('Request: ${request.method} ${request.url}');

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
          context: {'shelf.io.buffer_output': false}); // This seems to be the magic for streaming
    } else if (request.url.path == 'message' && request.method == 'POST') {
      print('Received message...');

      // Print the message body
      request.readAsString().then((body) {
        return processMessage(body);
      });

      return Response.ok('Message received');
    }

    // Log the request
    return Response.notFound('Not Found');
  }

  // Start the server
  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('Server listening on http://${server.address.host}:${server.port}');
}
