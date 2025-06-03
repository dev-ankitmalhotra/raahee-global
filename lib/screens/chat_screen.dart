import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:raahee_global_book_library/services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String bookId;
  final String? otherUserName;

  ChatScreen({
    super.key,
    required this.otherUserId,
    required this.bookId,
    this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _currentUserId;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: User not logged in.")),
          );
          Navigator.of(context).pop();
        }
      });
      _currentUserId = '';
      return;
    }
    _currentUserId = currentUser.uid;
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isNotEmpty && _currentUserId.isNotEmpty) {
      final chatDocId = _chatService.getChatDocumentId(
        _currentUserId,
        widget.otherUserId,
        widget.bookId,
      );
      await _chatService.sendMessage(
        chatDocId: chatDocId,
        senderId: _currentUserId,
        receiverId: widget.otherUserId,
        bookId: widget.bookId,
        text: _messageController.text.trim(),
      );
      _messageController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.otherUserName ?? 'Chat')),
        body: Center(child: Text("User not authenticated or error.")),
      );
    }
    
    final chatDocId = _chatService.getChatDocumentId(
      _currentUserId,
      widget.otherUserId,
      widget.bookId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName ?? 'Chat with ${widget.otherUserId.substring(0,6)}...'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatService.getMessages(chatDocId),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No messages yet. Start the conversation!'));
                }

                final messages = snapshot.data!.docs;
                
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  padding: EdgeInsets.all(8.0),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final messageText = message['text'] as String? ?? '';
                    final senderId = message['senderId'] as String? ?? '';
                    
                    final isMe = senderId == _currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isMe ? Theme.of(context).primaryColorLight : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                           boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          messageText,
                          style: TextStyle(color: isMe ? Colors.black87: Colors.black87),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
