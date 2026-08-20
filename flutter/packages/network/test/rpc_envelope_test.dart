import 'dart:convert';

import 'package:test/test.dart';

import 'package:network/rpc_envelope.dart';

void main() {
  test('client request keeps rpc identity', () {
    final request = ClientRequest(
      rpcId: 'rpc-1',
      method: 'session.prompt',
      payload: <String, Object?>{'sessionId': 's1'},
    );

    final wire = jsonEncode(request.toJson());
    final decoded = ClientRequest.fromJson(jsonDecode(wire));

    expect(decoded.rpcId, request.rpcId);
    expect(decoded.method, request.method);
  });
}
