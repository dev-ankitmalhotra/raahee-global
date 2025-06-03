import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart'; // Adjust the path if needed
import '../widgets/wishlist_button.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';

class BookDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> book;
  final String city;
  final String state;
  const BookDetailsScreen({required this.book, required this.city, required this.state, super.key});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  final FlutterTts flutterTts = FlutterTts();
  bool _showFullDescription = false;

  void _toggleDescription() {
    setState(() {
      _showFullDescription = !_showFullDescription;
    });
  }

  Future<bool> startStripePayment({
    required int amount, // in cents
    required String currency,
    required BuildContext context,
  }) async {
    try {
      // 1. Call your backend to create PaymentIntent
      final response = await http.post(
        Uri.parse('http://10.0.2.2:4242/create-payment-intent'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'amount': amount, 'currency': currency}),
      );
      final clientSecret = json.decode(response.body)['clientSecret'];

      // 2. Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Raahee Library',
          // applePay: const PaymentSheetApplePay(
          //   merchantCountryCode: 'US',
          // ),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: true,
          ),
          style: ThemeMode.light,
        ),
      );

      // 3. Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
      return false;
    }
  }

  Future<void> _speakBookDetails() async {
    final book = widget.book;
    final title = book['title'] ?? '';
    final author = book['author'] ?? '';
    final description = book['description'] ?? '';
    final text = 'Title: $title. Author: $author. Description: $description';
    await flutterTts.setLanguage('en-US');
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final city = widget.city;
    final state = widget.state;
    final theme = Theme.of(context);
    final description = book['description'] ?? 'No description available.';
    final descriptionTextStyle = theme.textTheme.bodyMedium;
    final titleTextStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);
    final authorTextStyle = theme.textTheme.bodyLarge;
    final categoryTextStyle = theme.textTheme.labelLarge?.copyWith(color: Colors.deepOrange);
    final ratingTextStyle = theme.textTheme.bodyLarge;
    final int totalCopies = (book['copies'] ?? 1) as int;
    final int rentedCopies = (book['rentedCopies'] ?? 0) as int;
    final int availableCopies = totalCopies - rentedCopies;
    final bool allRented = availableCopies <= 0;
    final bool isSold = book['isSold'] == true;
    final bool isUnavailable = allRented || isSold;

    return Scaffold(
      appBar: AppBar(
        title: Text(book['title'] ?? 'Book Details', style: titleTextStyle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.headphones),
            tooltip: 'Listen to Book Details',
            onPressed: _speakBookDetails,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Top Row: Cover + Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover (show image if available, else emoji)
              book['imageUrl'] != null && book['imageUrl'].toString().isNotEmpty
                ? Container(
                    height: 180,
                    width: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: NetworkImage(book['imageUrl']),
                        fit: BoxFit.cover,
                      ),
                      color: Colors.deepOrange.shade200,
                    ),
                  )
                : Container(
                    height: 180,
                    width: 130,
                    color: Colors.deepOrange.shade200,
                    child: Center(child: Text('📚', style: TextStyle(fontSize: 72))),
                  ),
              SizedBox(width: 24),
              // Book info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            book['title'] ?? 'No Title',
                            style: titleTextStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        WishlistButton(
                          bookId: book['id'],
                          bookData: book,
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    if (book['category'] != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          book['category'],
                          style: categoryTextStyle,
                        ),
                      ),
                    SizedBox(height: 10),
                    Text('Author: ${book['author'] ?? "Unknown"}', style: authorTextStyle),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        // Thumbs up
                        IconButton(
                          icon: Icon(Icons.thumb_up, color: Colors.green, size: 22),
                          tooltip: 'Like',
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) return;
                            final docRef = FirebaseFirestore.instance.collection('books').doc(book['id']);
                            final docSnap = await docRef.get();
                            final data = docSnap.data() as Map<String, dynamic>;
                            final List likedBy = (data['thumbsUpBy'] ?? []);
                            if (likedBy.contains(user.uid)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('You have already liked this book.')),
                              );
                              return;
                            }
                            await docRef.update({
                              'thumbsUp': FieldValue.increment(1),
                              'thumbsUpBy': FieldValue.arrayUnion([user.uid]),
                            });
                            setState(() {
                              book['thumbsUp'] = (book['thumbsUp'] ?? 0) + 1;
                              book['thumbsUpBy'] = [...likedBy, user.uid];
                            });
                          },
                        ),
                        Text((book['thumbsUp'] ?? 0).toString(), style: ratingTextStyle),
                        SizedBox(width: 8),
                        // Thumbs down
                        IconButton(
                          icon: Icon(Icons.thumb_down, color: Colors.red, size: 22),
                          tooltip: 'Dislike',
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) return;
                            final docRef = FirebaseFirestore.instance.collection('books').doc(book['id']);
                            final docSnap = await docRef.get();
                            final data = docSnap.data() as Map<String, dynamic>;
                            final List dislikedBy = (data['thumbsDownBy'] ?? []);
                            if (dislikedBy.contains(user.uid)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('You have already disliked this book.')),
                              );
                              return;
                            }
                            await docRef.update({
                              'thumbsDown': FieldValue.increment(1),
                              'thumbsDownBy': FieldValue.arrayUnion([user.uid]),
                            });
                            setState(() {
                              book['thumbsDown'] = (book['thumbsDown'] ?? 0) + 1;
                              book['thumbsDownBy'] = [...dislikedBy, user.uid];
                            });
                          },
                        ),
                        Text((book['thumbsDown'] ?? 0).toString(), style: ratingTextStyle),
                        if ((book['copies'] ?? 1) > 1) ...[
                          SizedBox(width: 14),
                          Icon(Icons.menu_book, size: 18, color: Colors.deepOrange),
                          SizedBox(width: 2),
                          Text(
                            '${book['copies']}',
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          // Description with show more/less
          LayoutBuilder(
            builder: (context, constraints) {
              final span = TextSpan(text: description, style: descriptionTextStyle);
              final tp = TextPainter(
                text: span,
                maxLines: _showFullDescription ? null : 4,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: constraints.maxWidth);
              final isOverflowing = tp.didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: descriptionTextStyle,
                    maxLines: _showFullDescription ? null : 4,
                    overflow: _showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  if (isOverflowing)
                    TextButton(
                      onPressed: _toggleDescription,
                      child: Text(_showFullDescription ? 'Show less' : 'Show more'),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: 20),
          // Rent and Buy options
          if (book['canRent'] == true)
            Row(
              children: [
                Text('Rent: \$${book['rentPrice'] ?? '--'}/week', style: TextStyle(fontSize: 16)),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: (book['isSold'] == true || (book['copies'] ?? 1) - (book['rentedCopies'] ?? 0) <= 0)
                      ? null
                      : () async {
                          final price = (book['rentPrice'] * 100).toInt(); // Stripe expects cents
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Confirm Rent'),
                              content: Text('Do you want to rent this book for \$${book['rentPrice']}?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Confirm')),
                              ],
                            ),
                          );
                          if (confirmed != true) return;

                          final paid = await startStripePayment(
                            amount: price,
                            currency: 'usd',
                            context: context,
                          );
                          if (paid) {
                            // Update Firestore for multi-copy logic
                            final user = FirebaseAuth.instance.currentUser;
                            final docRef = FirebaseFirestore.instance.collection('books').doc(book['id']);
                            final docSnap = await docRef.get();
                            final data = docSnap.data() as Map<String, dynamic>;
                            final int totalCopies = (data['copies'] ?? 1) as int;
                            final int rentedCopies = (data['rentedCopies'] ?? 0) as int;
                            final int newRentedCopies = rentedCopies + 1;
                            final bool allRented = newRentedCopies >= totalCopies;
                            await docRef.update({
                              'rentedCopies': FieldValue.increment(1),
                              'isRented': allRented,
                              'rentedBy': user!.uid, // Optionally, you may want to keep a list of renters for multi-copy
                              'dueDate': DateTime.now().add(Duration(days: 7)),
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Book rented successfully!')),
                            );
                            Navigator.of(context).pop();
                          }
                        },
                  style: ButtonStyle(
                    foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey;
                      }
                      return Theme.of(context).colorScheme.onPrimary;
                    }),
                    backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey.shade300;
                      }
                      return Theme.of(context).colorScheme.primary;
                    }),
                  ),
                  child: Text('Rent'),
                ),
              ],
            ),
          if (book['canBuy'] == true)
            Row(
              children: [
                Text('Buy: \$${book['buyPrice'] ?? '--'}', style: TextStyle(fontSize: 16)),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: (book['isSold'] == true) ? null : () async {
                    final price = (book['buyPrice'] * 100).toInt(); // Stripe expects cents
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Confirm Purchase'),
                        content: Text('Do you want to buy this book for \$${book['buyPrice']}?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Confirm')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;

                    final paid = await startStripePayment(
                      amount: price,
                      currency: 'usd',
                      context: context,
                    );
                    if (paid) {
                      // Update Firestore
                      final user = FirebaseAuth.instance.currentUser;
                      final docRef = FirebaseFirestore.instance.collection('books').doc(book['id']);
                      await docRef.update({
                        'isSold': true,
                        'soldTo': user!.uid,
                        'soldDate': DateTime.now(),
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Book purchased successfully!')),
                      );
                      // Pop only the BookDetailsScreen to return to the parent (e.g., HomeScreen)
                      Navigator.of(context).pop();
                    }
                  },
                  style: ButtonStyle(
                    foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey;
                      }
                      return Theme.of(context).colorScheme.onPrimary;
                    }),
                    backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey.shade300;
                      }
                      return Theme.of(context).colorScheme.primary;
                    }),
                  ),
                  child: Text('Buy'),
                ),
              ],
            ),
          // SizedBox(height: 20),
          // // Comments
          // Text('Comments', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          ...((book['comments'] ?? []) as List)
              .map((c) => ListTile(
                    leading: CircleAvatar(
                      child: Text((c['user'] ?? '?')[0]),
                    ),
                    title: Text(c['user'] ?? 'Anonymous'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['text'] ?? ''),
                        SizedBox(height: 4),
                        Text(
                          c['date'] != null
                              ? (c['date'] is DateTime
                                  ? '${c['date'].toLocal()}'.split(' ')[0]
                                  : c['date'].toString())
                              : '',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  )),
          SizedBox(height: 24),
          // Comment Section (after book details)
          Text('Comments', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          CommentSection(bookId: book['id']),
          SizedBox(height: 24),
          // Similar Books from Firestore (filtered by city and state)
          Text('Similar Books', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('books')
                  .where('category', isEqualTo: book['category'])
                  .where('id', isNotEqualTo: book['id'])
                  .where('city', isEqualTo: city)
                  .where('state', isEqualTo: state)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                final similarBooks = snapshot.data!.docs;
                if (similarBooks.isEmpty) return Center(child: Text('No similar books found.'));
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: similarBooks.length,
                  separatorBuilder: (_, __) => SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final similar = similarBooks[i].data() as Map<String, dynamic>;
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookDetailsScreen(book: similar, city: city, state: state),
                          ),
                        );
                      },
                      child: Container(
                        width: 160,
                        margin: EdgeInsets.only(right: 4),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 1.2,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: similar['imageUrl'] != null && similar['imageUrl'].toString().isNotEmpty
                                      ? Image.network(
                                          similar['imageUrl'],
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(child: Text('📚', style: TextStyle(fontSize: 32)));
                                          },
                                        )
                                      : Container(
                                          color: Colors.deepOrange.shade200,
                                          child: Center(child: Text('📚', style: TextStyle(fontSize: 32))),
                                        ),
                                ),
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              (similar['title'] ?? 'No Title').toString(),
                              style: TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 18),
                                SizedBox(width: 4),
                                Text(
                                  (similar['rating'] ?? 4.5).toString(),
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (similar['canRent'] == true)
                                  TextButton(
                                    onPressed: (similar['isSold'] == true || (similar['copies'] ?? 1) - (similar['rentedCopies'] ?? 0) <= 0)
                                        ? null
                                        : () {},
                                    style: ButtonStyle(
                                      foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                                        if (states.contains(MaterialState.disabled)) {
                                          return Colors.grey;
                                        }
                                        return Theme.of(context).colorScheme.primary;
                                      }),
                                    ),
                                    child: Text('Rent'),
                                  ),
                                if (similar['canBuy'] == true)
                                  TextButton(
                                    onPressed: (similar['isSold'] == true) ? null : () {},
                                    style: ButtonStyle(
                                      foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                                        if (states.contains(MaterialState.disabled)) {
                                          return Colors.grey;
                                        }
                                        return Theme.of(context).colorScheme.primary;
                                      }),
                                    ),
                                    child: Text('Buy'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Comment Section Widget ---
class CommentSection extends StatefulWidget {
  final String bookId;
  const CommentSection({required this.bookId, Key? key}) : super(key: key);

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  int _commentsToShow = 2;
  bool _loadingMore = false;

  Future<void> _submitComment() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _controller.text.trim();
    if (user == null || text.isEmpty) return;

    // List of banned words/phrases (add more as needed)
    final bannedWords = [
      'badword1', 'badword2', 'offensive', 'hate', 'racist', 'sexist', 'profanity',
      // Add more banned words/phrases here
    ];
    final lowerText = text.toLowerCase();
    final containsBanned = bannedWords.any((w) =>
      RegExp(r'\\b' + RegExp.escape(w) + r'\\b', caseSensitive: false).hasMatch(lowerText)
    );
    if (containsBanned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Your comment contains inappropriate language and cannot be submitted.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    await FirebaseFirestore.instance.collection('comments').add({
      'bookId': widget.bookId,
      'userId': user.uid,
      'userName': user.displayName ?? 'Anonymous',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _controller.clear();
    setState(() => _isSubmitting = false);
  }

  void _loadMore() {
    setState(() {
      _loadingMore = true;
      _commentsToShow += 5;
    });
    // No need to delay, StreamBuilder will update automatically
    setState(() {
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final emojiList = [
      '📚', '📖', '🤓', '😂', '😎', '🦉', '📝', '🤩', '🧠', '☕️'
    ];
    void _showEmojiPicker() async {
      final emoji = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          padding: EdgeInsets.all(16),
          children: emojiList.map((e) => GestureDetector(
            onTap: () => Navigator.pop(ctx, e),
            child: Center(child: Text(e, style: TextStyle(fontSize: 28))),
          )).toList(),
        ),
      );
      if (emoji != null) {
        final text = _controller.text;
        final selection = _controller.selection;
        final newText = text.replaceRange(
          selection.start,
          selection.end,
          emoji,
        );
        _controller.text = newText;
        final pos = selection.start + emoji.length;
        _controller.selection = TextSelection.collapsed(offset: pos);
        setState(() {});
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.emoji_emotions_outlined),
                    tooltip: 'Add emoji',
                    onPressed: _isSubmitting ? null : _showEmojiPicker,
                  ),
                ),
                minLines: 1,
                maxLines: 3,
                enabled: !_isSubmitting,
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSubmitting || _controller.text.trim().isEmpty ? null : _submitComment,
              child: _isSubmitting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send),
              style: ElevatedButton.styleFrom(minimumSize: Size(40, 40), padding: EdgeInsets.zero),
            ),
          ],
        ),
        SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('comments')
              .where('bookId', isEqualTo: widget.bookId)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
            final comments = snapshot.data!.docs;
            if (comments.isEmpty) return Text('No comments yet.');
            final showComments = comments.take(_commentsToShow).toList();
            return Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: showComments.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final c = showComments[i].data() as Map<String, dynamic>;
                    final userName = c['userName'] ?? 'Anonymous';
                    final text = c['text'] ?? '';
                    final timestamp = c['timestamp'] as Timestamp?;
                    final dateStr = timestamp != null ? (timestamp.toDate().toLocal().toString().split(' ')[0]) : '';
                    return ListTile(
                      leading: CircleAvatar(child: Text(userName[0])),
                      title: Text(userName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(text),
                          SizedBox(height: 4),
                          Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
                if (comments.length > _commentsToShow)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _loadingMore ? null : _loadMore,
                      child: _loadingMore ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Read more'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// In your onTap for a book (home_screen.dart or similar)
// Example usage (move this to the appropriate widget's onTap callback):
// onTap: () {
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     builder: (_) => FractionallySizedBox(
//       heightFactor: 0.95,
//       child: BookDetailsScreen(book: book),
//     ),
//   );
// },