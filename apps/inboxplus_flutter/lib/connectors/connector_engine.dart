import 'dart:async';

typedef ConnectorEvent = Map<String, Object?>;

abstract interface class ConnectorEngine {
  Stream<ConnectorEvent> get events;
  Future<Map<String, Object?>> request(Map<String, Object?> command);
  Future<void> close();
}

class ConnectorException implements Exception {
  const ConnectorException(this.code);
  final String code;

  @override
  String toString() => 'Messaging operation failed ($code).';
}
