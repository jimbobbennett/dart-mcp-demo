import 'dart:convert';

// Helper class to handle JsonRPC messages.
//
// This is hard coded with a single tool - ask pieces LTM, which returns some mock data
class JsonRpcMessage {
  // The JsonRPC method
  final String method;

  // The parameters for the method
  final dynamic params;

  // The id of the message. All responses must send the same id back.
  final int id;

  JsonRpcMessage(this.method, this.params, this.id);

  factory JsonRpcMessage.fromJson(Map<String, dynamic> json) {
    return JsonRpcMessage(json['method'], json['params'], json['id']);
  }

  Map<String, dynamic> toJson() {
    return {'jsonrpc': '2.0', 'method': method, 'params': params, 'id': id};
  }

  // Add a toString method
  @override
  String toString() {
    return 'JsonRpcMessage{method: $method, params: $params, id: $id}';
  }
}

// Handler to manage the JsonRPC messages
class JsonRpcHandler {
  // Depending on the message method, route to the relevant function and return a response
  String getResponseForRequest(JsonRpcMessage message) {
    switch (message.method) {
      case 'initialize':
        // https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization
        print('initialize');
        return _initialize(message.id);
      case 'tools/list':
        // https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/#listing-tools
        print('tools/list');
        return _listTools(message.id);
      case 'tools/call':
        // https://spec.modelcontextprotocol.io/specification/2024-11-05/server/tools/#calling-tools
        print('tools/call');
        return _callTool(message.id, message.params['name'], message.params['arguments']);
      case 'ping':
        // https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/ping/
        print('ping');
        return json.encode({'jsonrpc': '2.0', 'id': message.id, 'method': 'ping'});
      default:
        // We don't handle this method, so return an error
        return json.encode({
          'jsonrpc': '2.0',
          'error': {'code': -32601, 'message': 'Method not found'},
          'id': message.id
        });
    }
  }

  String _initialize(id) {
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

  String _listTools(id) {
    return json.encode({
      'jsonrpc': '2.0',
      'id': id,
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

  String _callTool(id, tool, arguments) {
    return json.encode({
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'content': [
          {'type': 'text', 'text': 'Current weather in New York:\nTemperature: 72°F\nConditions: Partly cloudy'}
        ],
        'isError': false
      }
    });
  }
}
