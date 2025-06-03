import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'book_details_screen.dart'; // Import the BookDetailsScreen
// Adjust path as needed
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_book_screen.dart'; // Import the AddBookScreen
import '../main.dart'; // Adjust path if needed
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/wishlist_button.dart';
import '../widgets/generic_app_bar.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<String> categories = [];
  final Set<String> selectedCategories = {};
  String selectedLocation = "Current Location";

  List<Map<String, dynamic>> books = [];
  List<Map<String, dynamic>> newBooks = [];
  bool isLoading = true;
  bool hideUnavailable = false;

  @override
  void initState() {
    super.initState();
    print('HomeScreen: initState');

    WidgetsBinding.instance.addObserver(this);

    // Load saved location
    _loadSavedLocation();

    // Fetch distinct categories
    fetchDistinctCategories().then((fetchedCategories) {
      setState(() {
        categories.clear();
        categories.addAll(fetchedCategories);
      });
    });
  }

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocation = prefs.getString('selectedLocation') ?? "Current Location";

    if (mounted) {
      setState(() {
        selectedLocation = savedLocation;
      });
    }

    // Fetch books for the saved location
    final parts = savedLocation.split(', ');
    if (parts.length == 2) {
      final city = parts[0];
      final state = parts[1];

      final fetchedBooks = await fetchBooksByLocation(city, state);
      if (mounted) {
        setState(() {
          books = fetchedBooks;
        });
      }

      final fetchedNewBooks = await fetchNewBooks(city, state);
      if (mounted) {
        setState(() {
          newBooks = fetchedNewBooks;
          isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<String> getCurrentLocationLabel() async {
    try {
      final response = await http.get(Uri.parse('https://ipinfo.io/json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final city = data['city'] ?? '';
        final state = data['region'] ?? '';
        if (city.isNotEmpty && state.isNotEmpty) {
          return '$city, $state';
        } else if (city.isNotEmpty) {
          return city;
        } else if (state.isNotEmpty) {
          return state;
        }
      }
    } catch (e) {
      print('Location fetch error: $e');
    }
    return "Unknown Location";
  }

  List<Map<String, dynamic>> filterBooksByCategory(String category) {
    return books.where((book) {
      final bookCategory = book['category'];
      if (bookCategory is String) { // Ensure the category is a String
        return bookCategory.toLowerCase() == category.toLowerCase(); // Case-insensitive comparison
      }
      return false; // Exclude books with invalid or missing category
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
          title: 'RAAHEE',
          onNotificationTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification tapped!')),
            );
          },
          onMenuTap: () {
            _scaffoldKey.currentState?.openDrawer();
          },
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).unselectedWidgetColor,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorWeight: 3.0,
            indicatorPadding: EdgeInsets.symmetric(horizontal: 8.0),
            tabs: [
              Tab(text: 'Popular'),
              Tab(text: 'New'),
              Tab(text: 'Browse'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Move the toggle to the top right, smaller size
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Hide unavailable', style: TextStyle(fontSize: 13)),
                  SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: hideUnavailable,
                      onChanged: (val) {
                        setState(() {
                          hideUnavailable = val;
                        });
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              // NESTED NAVIGATOR START
              child: Navigator(
                key: ValueKey('HomeTabNavigator'),
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(
                    builder: (context) => TabBarView(
                      children: [
                        // Tab 1: Popular
                        RefreshIndicator(
                          onRefresh: _refreshHomeScreen,
                          child: isLoading
                            ? ListView()
                            : books.isEmpty
                              ? ListView(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 80.0),
                                      child: Center(
                                        child: Text(
                                          'No books appear in your nearby location.\nBe the first to add books!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.all(16),
                                  itemCount: groupBooksByIsbn(hideUnavailable
                                    ? books.where((b) => b['isRented'] != true && b['isSold'] != true).toList()
                                    : books
                                  ).length,
                                  itemBuilder: (ctx, i) {
                                    final grouped = groupBooksByIsbn(hideUnavailable
                                      ? books.where((b) => b['isRented'] != true && b['isSold'] != true).toList()
                                      : books
                                    );
                                    final book = grouped[i];
                                    return BookRow(book: book, city: parseCityState(selectedLocation)['city']!, state: parseCityState(selectedLocation)['state']!);
                                  },
                                ),
                        ),

                        // Tab 2: New
                        RefreshIndicator(
                          onRefresh: _refreshHomeScreen,
                          child: isLoading
                            ? ListView()
                            : newBooks.isEmpty
                              ? ListView(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 80.0),
                                      child: Center(
                                        child: Text(
                                          'No new books found in your area.\nBe the first to add books!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.all(16),
                                  itemCount: groupBooksByIsbn(hideUnavailable
                                    ? newBooks.where((b) => b['isRented'] != true && b['isSold'] != true).toList()
                                    : newBooks
                                  ).length,
                                  itemBuilder: (ctx, i) {
                                    final grouped = groupBooksByIsbn(hideUnavailable
                                      ? newBooks.where((b) => b['isRented'] != true && b['isSold'] != true).toList()
                                      : newBooks
                                    );
                                    final book = grouped[i];
                                    return BookRow(book: book, city: parseCityState(selectedLocation)['city']!, state: parseCityState(selectedLocation)['state']!);
                                  },
                                ),
                        ),

                        // Tab 3: Browse
                        RefreshIndicator(
                          onRefresh: _refreshHomeScreen,
                          child: isLoading
                            ? ListView()
                            : categories.isEmpty
                              ? ListView(children: [Center(child: Text('No categories found.'))])
                              : ListView(
                                  padding: EdgeInsets.all(16),
                                  children: [
                                    DropdownButton<String>(
                                      value: selectedCategories.isNotEmpty ? selectedCategories.first : null,
                                      hint: Text('Select a category'),
                                      isExpanded: true,
                                      items: categories.map((category) {
                                        return DropdownMenuItem<String>(
                                          value: category,
                                          child: Text(category),
                                        );
                                      }).toList(),
                                      onChanged: (selectedCategory) {
                                        setState(() {
                                          selectedCategories.clear();
                                          if (selectedCategory != null) {
                                            selectedCategories.add(selectedCategory);
                                          }
                                        });
                                      },
                                    ),
                                    SizedBox(height: 16),
                                    if (selectedCategories.isEmpty)
                                      Center(child: Text('Please select a category to view books.'))
                                    else
                                      ...groupBooksByIsbn(hideUnavailable
                                        ? filterBooksByCategory(selectedCategories.first).where((b) => b['isRented'] != true && b['isSold'] != true).toList()
                                        : filterBooksByCategory(selectedCategories.first)
                                      ).map((book) => BookRow(book: book, city: parseCityState(selectedLocation)['city']!, state: parseCityState(selectedLocation)['state']!)).toList(),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // NESTED NAVIGATOR END
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (fabContext) => FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(fabContext).push(
                MaterialPageRoute(
                  builder: (_) => AddBookScreen(),
                ),
              );
            },
            icon: Icon(Icons.menu_book),
            label: Text('Add Book for Rent/Sell'),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    print('HomeScreen: dispose');
    // Unsubscribe from RouteObserver
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to RouteObserver
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    // This will be called when the screen is shown again
    _refreshHomeScreen();
  }

  @override
  void didPopNext() {
    // Called when coming back to this screen (e.g., after popping another route)
    _refreshHomeScreen();
  }

  Future<void> fetchData() async {
    try {
      final data = await someAsyncOperation();

      if (!mounted) return; // Exit if the widget is no longer mounted

      setState(() {
        books = data; // Update state with the fetched data
      });
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  Future<List<Map<String, dynamic>>> someAsyncOperation() async {
    await Future.delayed(Duration(seconds: 2)); // Simulate a delay
    return [
      {'title': 'Book 1', 'author': 'Author 1'},
      {'title': 'Book 2', 'author': 'Author 2'},
    ];
  }

  Future<void> _refreshHomeScreen() async {
    await _loadSavedLocation();
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class HorizontalBookList extends StatelessWidget {
  final List<Map<String, dynamic>> books;
  final String city;
  final String state;

  HorizontalBookList({required this.books, required this.city, required this.state});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        itemBuilder: (ctx, i) {
          return _buildBookCard(context, books[i]);
        },
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, Map<String, dynamic> book) {
    final isUnavailable = (book['isRented'] == true) || (book['isSold'] == true);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailsScreen(book: book, city: city, state: state),
          ),
        );
      },
      child: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 80,
              width: 160,
              color: Colors.deepOrange.shade200,
              child: (book['imageUrl'] != null && book['imageUrl'].isNotEmpty)
                  ? Image.network(
                      book['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(child: Text('📚', style: TextStyle(fontSize: 32)));
                      },
                    )
                  : Center(child: Text('📚', style: TextStyle(fontSize: 32))),
            ),
            SizedBox(height: 8),
            Text(book['title'] ?? 'No Title', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(Icons.thumb_up, color: Colors.green, size: 20),
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
                  },
                ),
                Text((book['thumbsUp'] ?? 0).toString(), style: TextStyle(fontWeight: FontWeight.w500)),
                SizedBox(width: 8),
                if ((book['copies'] ?? 1) > 1) ...[
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
                  SizedBox(width: 8),
                ],
                WishlistButton(
                  bookId: book['id'],
                  bookData: book,
                ),
                Spacer(),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                if (isUnavailable)
                  Chip(
                    label: Text(
                      book['isRented'] == true ? 'Rented' : 'Sold',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: Colors.grey.withOpacity(0.18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                  )
                else ...[
                  if (book['canRent'] == true)
                    Chip(
                      label: Text(
                        'Available for Rent',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                  if (book['canBuy'] == true)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Chip(
                        label: Text(
                          'Available for Purchase',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                if (book['canRent'] == true)
                  TextButton(
                    onPressed: isUnavailable ? null : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookDetailsScreen(book: book, city: city, state: state),
                        ),
                      );
                    },
                    child: Text('Rent'),
                  ),
                if (book['canBuy'] == true)
                  TextButton(
                    onPressed: isUnavailable ? null : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookDetailsScreen(book: book, city: city, state: state),
                        ),
                      );
                    },
                    child: Text('Buy'),
                  ),
              ],
            ),
          ],
        ),
      )
    );
  }
}

class BookRow extends StatelessWidget {
  final Map<String, dynamic> book;
  final String city;
  final String state;

  BookRow({required this.book, required this.city, required this.state});

  @override
  Widget build(BuildContext context) {
    final imageUrl = book['imageUrl']?.replaceFirst('http://', 'https://') ?? '';
    final isUnavailable = (book['isRented'] == true) || (book['isSold'] == true);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailsScreen(book: book, city: city, state: state),
          ),
        );
      },
      child: Card(
        margin: EdgeInsets.only(bottom: 12),
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover
              Container(
                height: 80,
                width: 60,
                color: Colors.deepOrange.shade200,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(child: Text('📚', style: TextStyle(fontSize: 32)));
                        },
                      )
                    : Center(child: Text('📚', style: TextStyle(fontSize: 32))),
              ),
              SizedBox(width: 12),
              // Book details and chips
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Book details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book['title'] ?? 'No Title',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            book['author'] ?? 'Unknown Author',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              // Thumbs up only
                              IconButton(
                                icon: Icon(Icons.thumb_up, color: Colors.green, size: 20),
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
                                },
                              ),
                              Text((book['thumbsUp'] ?? 0).toString(), style: TextStyle(fontWeight: FontWeight.w500)),
                              SizedBox(width: 8),
                              if ((book['copies'] ?? 1) > 1) ...[
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
                              Spacer(),
                              if (isUnavailable)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Chip(
                                    label: Text(
                                      book['isRented'] == true ? 'Rented' : 'Sold',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    backgroundColor: Colors.grey.withOpacity(0.18),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                )
                              else ...[
                                if (book['canRent'] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Chip(
                                      label: Text(
                                        'Available for Rent',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                  ),
                                if (book['canBuy'] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Chip(
                                      label: Text(
                                        'Available for Purchase',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.secondary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.symmetric(horizontal: 8),
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
              ),
            ],
          ),
        ),
      )
    ); // closes GestureDetector
  }
}

// Helper to parse city and state from selectedLocation
Map<String, String> parseCityState(String selectedLocation) {
  final parts = selectedLocation.split(', ');
  if (parts.length == 2) {
    return {'city': parts[0], 'state': parts[1]};
  }
  return {'city': '', 'state': ''};
}

Future<List<Map<String, dynamic>>> fetchBooksByLocation(String city, String state) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('books')
        .where('city', isEqualTo: city)
        .where('state', isEqualTo: state)
        .get();

    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        })
        .where((book) => (book['isbn13'] ?? '').toString().isNotEmpty) // Only books with isbn13
        .toList();
  } catch (e) {
    print('Error fetching books by location: $e');
    return [];
  }
}

Future<List<Map<String, dynamic>>> fetchNewBooks(String city, String state) async {
  try {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(Duration(days: 7));
    final snapshot = await FirebaseFirestore.instance
        .collection('books')
        .where('city', isEqualTo: city)
        .where('state', isEqualTo: state)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
        .get();

    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        })
        .where((book) => (book['isbn13'] ?? '').toString().isNotEmpty) // Only books with isbn13
        .toList();
  } catch (e) {
    print('Error fetching new books: $e');
    return [];
  }
}

Future<List<String>> fetchDistinctCategories() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('books')
        .get();

    final categories = snapshot.docs
        .expand((doc) {
          final category = doc['category'];
          if (category is String) {
            return [category];
          } else if (category is List) {
            return category.cast<String>();
          }
          return [];
        })
        .toSet()
        .toList()
        .cast<String>();

    print('Fetched categories: $categories');
    return categories;
  } catch (e) {
    print('Error fetching categories: $e');
    return [];
  }
}

List<Map<String, dynamic>> groupBooksByIsbn(List<Map<String, dynamic>> books) {
  final Map<String, Map<String, dynamic>> grouped = {};
  final Map<String, int> counts = {};

  for (var book in books) {
    final isbn = book['isbn13'] ?? '';
    if (isbn.isEmpty) continue;

    if (!grouped.containsKey(isbn)) {
      grouped[isbn] = Map<String, dynamic>.from(book);
      counts[isbn] = 1;
    } else {
      counts[isbn] = counts[isbn]! + 1;
    }
  }

  // Add the count to each grouped book
  for (var isbn in grouped.keys) {
    grouped[isbn]!['copies'] = counts[isbn];
  }

  return grouped.values.toList();
}



