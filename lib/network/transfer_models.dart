import 'dart:io';

class TransferFile {
  final String id;
  final File file;
  final String fileName;
  final int size;
  final String mimeType;
  final String sha256;

  const TransferFile({
    required this.id,
    required this.file,
    required this.fileName,
    required this.size,
    required this.mimeType,
    required this.sha256,
  });
}

enum TransferDirection { send, receive }
enum TransferStatus { waiting, transferring, completed, failed, cancelled }

class TransferRecord {
  final String id;
  final String peer;
  final String fileName;
  final int size;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime createdAt;

  const TransferRecord({
    required this.id,
    required this.peer,
    required this.fileName,
    required this.size,
    required this.direction,
    required this.status,
    required this.createdAt,
  });
}
