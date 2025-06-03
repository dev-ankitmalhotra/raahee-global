import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/book_details_screen.dart';
import 'package:rxdart/rxdart.dart';

class GenericAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onNotificationTap;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onMenuTap; // <-- Add callback for menu

  const GenericAppBar({
    Key? key,
    required this.title,
    this.onNotificationTap,
    this.actions,
    this.bottom,
    this.onMenuTap, // <-- Add to constructor
  }) : super(key: key);

  @override
  State<GenericAppBar> createState() => _GenericAppBarState();

  @override
  Size get preferredSize {
    // If bottom is present, add its height to the toolbar height
    final bottomHeight = bottom?.preferredSize.height ?? 0.0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }
}

class _GenericAppBarState extends State<GenericAppBar> {
  String _location = "Current Location";

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
  }

  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocation = prefs.getString('selectedLocation') ?? "Current Location";
    setState(() {
      _location = savedLocation;
    });
  }

  Future<void> _detectLocation() async {
    try {
      final response = await http.get(Uri.parse('https://ipinfo.io/json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final city = data['city'] ?? '';
        final state = data['region'] ?? '';
        final location = (city.isNotEmpty && state.isNotEmpty)
            ? '$city, $state'
            : (city.isNotEmpty ? city : (state.isNotEmpty ? state : "Unknown Location"));
        setState(() {
          _location = location;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selectedLocation', location);
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _showLocationDialog() async {
    String tempLocation = _location;
    final newLocation = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Change Location"),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(hintText: "Enter new location"),
            controller: TextEditingController(text: tempLocation),
            onChanged: (value) => tempLocation = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, tempLocation),
              child: Text("Save"),
            ),
          ],
        );
      },
    );
    if (newLocation != null && newLocation.isNotEmpty) {
      setState(() {
        _location = newLocation;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedLocation', newLocation);
    }
  }

  void _startSearch() async {
    await showSearch(
      context: context,
      delegate: BookSearchDelegate(
        initialLocation: _location,
        onLocationChanged: (loc) async {
          setState(() { _location = loc; });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('selectedLocation', loc);
        },
      ),
    );
    // Optionally handle result
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? (isDark ? Colors.grey[900] : Colors.white),
      elevation: 2,
      leading: IconButton(
        icon: Icon(Icons.menu, color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange),
        onPressed: widget.onMenuTap,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _detectLocation,
                child: Icon(Icons.location_on, size: 16, color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange),
              ),
              SizedBox(width: 4),
              GestureDetector(
                onTap: _showLocationDialog,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _location,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange,
                      ),
                    ),
                    Icon(Icons.edit, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange),
          onPressed: _startSearch,
        ),
        IconButton(
          icon: Icon(Icons.notifications_none, color: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange),
          onPressed: widget.onNotificationTap,
        ),
        if (widget.actions != null) ...widget.actions!,
      ],
      bottom: widget.bottom,
    );
  }
}

class BookSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  String location;
  final String initialLocation;
  final Future<void> Function(String) onLocationChanged;

  BookSearchDelegate({required this.initialLocation, required this.onLocationChanged}) : location = initialLocation;

  @override
  String get searchFieldLabel => 'Type a book title or author name to search.';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.location_on),
        tooltip: 'Change Location',
        onPressed: () async {
          final newLoc = await showDialog<String>(
            context: context,
            builder: (context) {
              String tempLocation = location;
              return AlertDialog(
                title: Text("Change Location"),
                content: TextField(
                  autofocus: true,
                  decoration: InputDecoration(hintText: "Enter new location"),
                  controller: TextEditingController(text: tempLocation),
                  onChanged: (value) => tempLocation = value,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: Text("Cancel"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, tempLocation),
                    child: Text("Save"),
                  ),
                ],
              );
            },
          );
          if (newLoc != null && newLoc.isNotEmpty) {
            location = newLoc;
            await onLocationChanged(newLoc);
            showSuggestions(context);
          }
        },
      ),
      if (query.isNotEmpty)
        IconButton(
          icon: Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return Center(child: Text('Type a book title or author name to search.'));
    }
    final lowerQuery = query.toLowerCase();
    final city = location.split(', ').first;
    final state = location.split(', ').last;
    final booksQuery = FirebaseFirestore.instance
        .collection('books')
        .where('city', isEqualTo: city)
        .where('state', isEqualTo: state)
        .where('search_keywords', arrayContains: lowerQuery)
        .limit(20)
        .snapshots();
    return StreamBuilder<QuerySnapshot>(
      stream: booksQuery,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
        final results = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();
        if (results.isEmpty) {
          return Center(child: Text('No books found for "$query" in $city, $state.'));
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => Divider(),
          itemBuilder: (ctx, i) {
            final book = results[i];
            final int totalCopies = (book['copies'] ?? 1) as int;
            final int rentedCopies = (book['rentedCopies'] ?? 0) as int;
            final int availableCopies = totalCopies - rentedCopies;
            final bool allRented = availableCopies <= 0;
            final bool isSold = book['isSold'] == true;
            final bool isUnavailable = allRented || isSold;
            return ListTile(
              leading: book['imageUrl'] != null && book['imageUrl'].toString().isNotEmpty
                  ? Image.network(book['imageUrl'], width: 40, height: 60, fit: BoxFit.cover)
                  : Icon(Icons.book, size: 40),
              title: Row(
                children: [
                  Expanded(child: Text(book['title'] ?? 'No Title')),
                  if (isSold)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Chip(
                        label: Text('Sold', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                        backgroundColor: Colors.grey.withOpacity(0.18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.symmetric(horizontal: 6),
                      ),
                    )
                  else if (allRented)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Chip(
                        label: Text('Rented', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                        backgroundColor: Colors.grey.withOpacity(0.18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                ],
              ),
              subtitle: Text(book['author'] ?? 'Unknown Author'),
              onTap: () {
                close(ctx, book);
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => BookDetailsScreen(
                      book: book,
                      city: city,
                      state: state,
                    ),
                  ),
                );
              },
              enabled: true,
            );
          },
        );
      },
    );
  }
}