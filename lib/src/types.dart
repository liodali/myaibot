/// Chatwoot webhook & message models (manual JSON parsing, no codegen).
library;

import 'dart:convert';

class ChatwootMessage {
  final int? id;
  final String? content;
  final String? messageType; // incoming | outgoing | activity | template
  final bool privateMessage;
  final dynamic createdAt;
  final int? senderId;
  final String? senderName;

  const ChatwootMessage({
    this.id,
    this.content,
    this.messageType,
    this.privateMessage = false,
    this.createdAt,
    this.senderId,
    this.senderName,
  });

  static ChatwootMessage fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    return ChatwootMessage(
      id: json['id'] is int ? json['id'] as int : null,
      content: json['content']?.toString(),
      messageType: json['message_type']?.toString(),
      privateMessage: json['private'] == true,
      createdAt: json['created_at'],
      senderId:
          sender is Map<String, dynamic> && sender['id'] is int
              ? sender['id'] as int
              : null,
      senderName:
          sender is Map<String, dynamic> ? sender['name']?.toString() : null,
    );
  }
}

class ChatwootEvent {
  final String event;
  final int? id;
  final dynamic content;
  final String? messageType;
  final bool privateMessage;
  final int? accountId;
  final int? conversationId;
  final String? conversationStatus;
  final int? inboxId;

  const ChatwootEvent({
    required this.event,
    this.id,
    this.content,
    this.messageType,
    this.privateMessage = false,
    this.accountId,
    this.conversationId,
    this.conversationStatus,
    this.inboxId,
  });

  /// Parse a Chatwoot webhook payload. Throws [FormatException] on bad JSON.
  static ChatwootEvent parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('webhook payload is not a JSON object');
    }
    return fromJson(decoded);
  }

  static ChatwootEvent fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    final conversation = json['conversation'];
    return ChatwootEvent(
      event: json['event']?.toString() ?? '',
      id: json['id'] is int ? json['id'] as int : null,
      content: json['content'],
      messageType: json['message_type']?.toString(),
      privateMessage: json['private'] == true,
      accountId:
          account is Map<String, dynamic> && account['id'] is int
              ? account['id'] as int
              : null,
      conversationId:
          conversation is Map<String, dynamic> && conversation['id'] is int
              ? conversation['id'] as int
              : null,
      conversationStatus:
          conversation is Map<String, dynamic>
              ? conversation['status']?.toString()
              : null,
      inboxId:
          json['inbox'] is Map<String, dynamic> &&
                  (json['inbox'] as Map<String, dynamic>)['id'] is int
              ? (json['inbox'] as Map<String, dynamic>)['id'] as int
              : null,
    );
  }
}
