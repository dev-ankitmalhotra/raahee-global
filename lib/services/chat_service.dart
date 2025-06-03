import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generates a consistent chat document ID for two users and a book
  String getChatDocumentId(String userId1, String userId2, String bookId) {
    List<String> ids = [userId1, userId2];
    ids.sort(); // Sort to ensure consistency regardless of user order
    return '${ids[0]}_${ids[1]}_$bookId';
  }

  // Get a stream of messages for a chat, ordered by timestamp
  Stream<QuerySnapshot> getMessages(String chatDocId) {
    return _firestore
        .collection('chats')
        .doc(chatDocId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Send a message
  Future<void> sendMessage({
    required String chatDocId,
    required String senderId,
    required String receiverId,
    required String bookId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final messageData = {
      'senderId': senderId,
      'receiverId': receiverId, // Storing receiverId for clarity/future use
      'bookId': bookId, // Denormalized for potential direct queries on messages
      'text': text,
      'timestamp': FieldValue.serverTimestamp(), // Uses server time
    };

    // Add the message to the 'messages' subcollection
    await _firestore
        .collection('chats')
        .doc(chatDocId)
        .collection('messages')
        .add(messageData);

    // Update the main chat document with last message info (optional, but useful for chat lists)
    await _firestore.collection('chats').doc(chatDocId).set({
      'users': [senderId, receiverId], // Store involved users
      'bookId': bookId,
      'lastMessage': text,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // Use merge to avoid overwriting existing fields
  }
}
