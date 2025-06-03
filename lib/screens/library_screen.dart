import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../widgets/generic_app_bar.dart';
import '../widgets/wishlist_button.dart';
import '../main.dart'; // <-- Add this line with your other imports
import 'chat_screen.dart'; // Import the ChatScreen


class LibraryScreen extends StatefulWidget {
  final int initialTab;
  const LibraryScreen({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.account_circle, size: 48, color: Colors.white),
                      SizedBox(height: 8),
                      Text(
                        FirebaseAuth.instance.currentUser?.email ?? 'Profile',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, mode, _) {
                    return SwitchListTile(
                      title: Text('Dark Theme'),
                      value: mode == ThemeMode.dark,
                      onChanged: (isDark) {
                        themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
                      },
                      secondary: Icon(
                        mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Logout'),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
        appBar: GenericAppBar(
          title: 'My Library',
          onNotificationTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification tapped!')),
            );
          },
          onMenuTap: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        body: Column(
          children: [
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: TabBar(
                labelColor: Colors.deepOrange,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.deepOrange,
                indicatorWeight: 3.0,
                tabs: [
                  Tab(text: 'Rented'),
                  Tab(text: 'Advertised'),
                  Tab(text: 'Purchased'),
                  Tab(text: 'Wishlist'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RentedTab(),
                  _AdvertisedTab(),
                  _PurchasedTab(),
                  _WishlistTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Rented Tab
class _RentedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .where('isRented', isEqualTo: true)
          .where('rentedBy', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final books = snapshot.data!.docs;
        if (books.isEmpty) {
          return Center(child: Text('No rented books.'));
        }
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final bookDocument = books[index]; // Get the DocumentSnapshot
            final book = bookDocument.data() as Map<String, dynamic>;
            final bookId = bookDocument.id; // Get the book ID from the document
            final advertiserId = book['userId'] as String?; // Get the advertiser's ID

            return Stack(
              children: [
                BookRow(
                  book: book,
                  showDueDate: true, // Rented books have due dates
                  otherUserId: advertiserId, // Pass advertiser's ID as otherUserId
                  bookId: bookId,     // Pass bookId
                  // otherUserName: fetch advertiserName if needed, or pass a default
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(Icons.alarm, color: Colors.deepOrange),
                    tooltip: 'Set Reminder',
                    onPressed: () async {
                      DateTime? dueDate;
                      if (book['dueDate'] != null) {
                        // Firestore Timestamp to DateTime
                        dueDate = (book['dueDate'] is Timestamp)
                            ? (book['dueDate'] as Timestamp).toDate()
                            : DateTime.tryParse(book['dueDate'].toString());
                      }

                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: dueDate ?? DateTime.now().add(Duration(days: 7)),
                      );
                      if (picked != null) {
                        // Optionally, show a time picker here as well
                        // Schedule local notification
                        final plugin = FlutterLocalNotificationsPlugin();
                        await plugin.initialize(
                          InitializationSettings(
                            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                            iOS: DarwinInitializationSettings(),
                          ),
                        );
                        await plugin.zonedSchedule(
                          0,
                          'Book Return Reminder',
                          'Return "${book['title']}" by due date!',
                          tz.TZDateTime.from(picked, tz.local),
                          const NotificationDetails(
                            android: AndroidNotificationDetails('reminder_channel', 'Reminders'),
                            iOS: DarwinNotificationDetails(),
                          ),
                          androidAllowWhileIdle: false, // <-- set to false
                          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime, // <-- not absoluteTime
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Reminder set for ${picked.day}/${picked.month}/${picked.year}')),
                        );
                      }
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Advertised Tab
class _AdvertisedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final books = snapshot.data!.docs;
        if (books.isEmpty) {
          return Center(child: Text('No advertised books.'));
        }
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final bookDocument = books[index];
            final bookData = bookDocument.data() as Map<String, dynamic>;
            final bookId = bookDocument.id;
            // For advertised books, the user wants to message someone who has interacted (rented/purchased)
            // This requires knowing who the 'otherUser' is. 
            // If the book is rented, otherUserId is 'rentedBy'.
            // If the book is sold, otherUserId is 'soldTo'.
            // We need to determine if we should show a button and who to message.
            // This might be complex if a book can be rented by one user and later sold to another.
            // For simplicity, let's assume we want to message 'rentedBy' if available, else 'soldTo'.
            
            String? otherUserIdForChat;
            String? otherUserNameForChat; // You'll likely need to fetch this based on otherUserIdForChat

            if (bookData['isRented'] == true && bookData['rentedBy'] != null) {
              otherUserIdForChat = bookData['rentedBy'] as String?;
              // TODO: Fetch renter's name using otherUserIdForChat if needed for AppBar title
              // otherUserNameForChat = await fetchUserName(otherUserIdForChat);
            } else if (bookData['isSold'] == true && bookData['soldTo'] != null) {
              otherUserIdForChat = bookData['soldTo'] as String?;
              // TODO: Fetch buyer's name using otherUserIdForChat if needed for AppBar title
              // otherUserNameForChat = await fetchUserName(otherUserIdForChat);
            }

            return Stack(
              children: [
                BookRow(
                  book: bookData,
                  bookId: bookId, // Pass bookId
                  otherUserId: otherUserIdForChat, // Pass the determined other user ID
                  otherUserName: otherUserNameForChat, // Pass the other user's name
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      bookData['status']?.toString() ?? '',
                      style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Purchased Tab
class _PurchasedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('books')
          .where('isSold', isEqualTo: true)
          .where('soldTo', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final books = snapshot.data!.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList();

        // Sort by soldDate descending
        books.sort((a, b) {
          final aDate = a['soldDate'] is Timestamp
              ? (a['soldDate'] as Timestamp).toDate()
              : DateTime.tryParse(a['soldDate']?.toString() ?? '');
          final bDate = b['soldDate'] is Timestamp
              ? (b['soldDate'] as Timestamp).toDate()
              : DateTime.tryParse(b['soldDate']?.toString() ?? '');
          return (bDate ?? DateTime(0)).compareTo(aDate ?? DateTime(0));
        });

        if (books.isEmpty) {
          return Center(child: Text('No purchased books.'));
        }
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final bookDocument = snapshot.data!.docs[index];
            final bookData = bookDocument.data() as Map<String, dynamic>; 
            final String bookId = bookDocument.id;
            final String? originalSellerId = bookData['userId'] as String?;

            return Stack(
              children: [
                BookRow(
                  book: bookData,
                  otherUserId: originalSellerId, // Pass the original seller's ID as otherUserId
                  bookId: bookId,
                  // otherUserName: fetch sellerName if needed or pass a default
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Purchased',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Wishlist Tab
class _WishlistTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('wishlist')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final wishlistBooks = snapshot.data!.docs;
        if (wishlistBooks.isEmpty) {
          return Center(child: Text('Your wishlist is empty.'));
        }
        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: wishlistBooks.length,
          itemBuilder: (context, index) {
            final book = wishlistBooks[index].data() as Map<String, dynamic>;
            return Stack(
              children: [
                BookRow(book: book),
                Positioned(
                  top: 8,
                  right: 8,
                  child: WishlistButton(
                    bookId: book['bookId'],
                    bookData: book,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class BookRow extends StatelessWidget {
  final Map<String, dynamic> book;
  final bool showDueDate;
  final String? otherUserId; // Changed from sellerId
  final String? bookId;
  final String? otherUserName; // Changed from sellerName

  const BookRow({
    Key? key,
    required this.book,
    this.showDueDate = false,
    this.otherUserId, // Changed from sellerId
    this.bookId,
    this.otherUserName, // Changed from sellerName
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DateTime? dueDate;
    if (showDueDate && book['dueDate'] != null) {
      // Firestore Timestamp to DateTime
      dueDate = (book['dueDate'] is Timestamp)
          ? (book['dueDate'] as Timestamp).toDate()
          : DateTime.tryParse(book['dueDate'].toString());
    }

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Book cover
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              book['imageUrl'],
              width: 64,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: 12),
          // Book details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book['title'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  book['author'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                if (showDueDate && dueDate != null) ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.deepOrange),
                      SizedBox(width: 4),
                      Text(
                        'Due: ${dueDate.day}/${dueDate.month}/${dueDate.year}',
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 8),
                Row(
                  children: [
                    // Left: Star, rating, copies
                    Expanded( // Wrap the existing Row in Expanded to make space for the button
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 18),
                          SizedBox(width: 4),
                          Text(
                            (book['rating'] ?? 0.0).toString(),
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if ((book['copies'] ?? 1) > 1) ...[
                            SizedBox(width: 12),
                            Icon(Icons.menu_book, size: 16, color: Colors.deepOrange),
                            SizedBox(width: 2),
                            Text(
                              '${book['copies']}',
                              style: TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Add Message button if otherUserId and bookId are available
                    if (otherUserId != null && bookId != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.chat_bubble_outline, size: 16),
                          label: Text('Message'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  otherUserId: otherUserId!, // Use the generic otherUserId
                                  bookId: bookId!,
                                  otherUserName: otherUserName ?? 'User', // Use the generic otherUserName
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
