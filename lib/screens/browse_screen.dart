import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/generic_app_bar.dart';
import '../main.dart';
import '../widgets/wishlist_button.dart';
import 'book_details_screen.dart';

class BrowseScreen extends StatefulWidget {
  @override
  _BrowseScreenState createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Map<MarkerId, Map<String, dynamic>> _markerBookMap = {};
  LatLng? _currentPosition;
  bool _loading = true;
  double _distance = 5.0; // Default distance in miles
  Map<String, dynamic>? _selectedBook;

  @override
  void initState() {
    super.initState();
    _handleLocationAndBooks();
  }

  Future<void> _handleLocationAndBooks() async {
    setState(() => _loading = true);

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location permission permanently denied. Please enable it in settings.')),
      );
      return;
    }

    // Permission granted, proceed
    await _initLocationAndBooks();
  }

  Future<void> _initLocationAndBooks() async {
    try {
      // 1. Get current location
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _currentPosition = LatLng(position.latitude, position.longitude);

      // 2. Fetch all books from Firestore
      final snapshot = await FirebaseFirestore.instance.collection('books').get();
      final books = snapshot.docs.map((doc) => doc.data()).toList();
      print('Fetched books: $books');

      // Filter out books without a non-empty isbn13
      final filteredBooks = books.where((book) {
        final isbn = (book['isbn13'] ?? '').toString();
        if (isbn.isEmpty) return false;
        if (book['lat'] == null || book['lng'] == null) return false;
        if (book['isRented'] == true) return false;
        if (book['isSold'] == true) return false;
        double distance = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          book['lat'],
          book['lng'],
        );
        return distance <= _distance;
      }).toList();
      print('Filtered books: $filteredBooks');

      // 4. Add markers for filtered books
      if (!mounted) return;
      setState(() {
        _markers.clear();
        for (var i = 0; i < filteredBooks.length; i++) {
          final book = filteredBooks[i];
          // Offset marker if multiple books at same location
          double lat = book['lat'];
          double lng = book['lng'];
          // Offset by a tiny amount if there are duplicates
          lat += i * 0.00002;
          lng += i * 0.00001;

          final markerId = MarkerId(book['isbn13'] ?? book['title'] ?? '$i');
          _markers.add(
            Marker(
              markerId: markerId,
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: book['title'] ?? '',
                onTap: () {
                  setState(() {
                    _selectedBook = book;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedBook = book;
                });
              },
            ),
          );
          _markerBookMap[markerId] = book;
        }
        _markers.add(
          Marker(
            markerId: MarkerId('user_location'),
            position: _currentPosition!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: 'You are here'),
          ),
        );
        _circles.clear();
        _circles.add(
          Circle(
            circleId: CircleId('search_radius'),
            center: _currentPosition!,
            radius: _distance * 1609.34, // miles to meters
            fillColor: Colors.blue.withOpacity(0.1),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          ),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading books or location: $e')),
      );
    }
  }

  Future<void> _updateBooksInView() async {
    if (_mapController == null) return;
    final bounds = await _mapController!.getVisibleRegion();

    // Fetch all books from Firestore (or cache them if you want)
    final snapshot = await FirebaseFirestore.instance.collection('books').get();
    final books = snapshot.docs.map((doc) => doc.data()).toList();

    // Filter books within visible region
    final filteredBooks = books.where((book) {
      final isbn = (book['isbn13'] ?? '').toString();
      if (isbn.isEmpty) return false;
      if (book['lat'] == null || book['lng'] == null) return false;
      if (book['isRented'] == true) return false;
      if (book['isSold'] == true) return false;
      final lat = book['lat'];
      final lng = book['lng'];
      return lat >= bounds.southwest.latitude &&
             lat <= bounds.northeast.latitude &&
             lng >= bounds.southwest.longitude &&
             lng <= bounds.northeast.longitude;
    }).toList();

    setState(() {
      _markers.clear();
      for (var i = 0; i < filteredBooks.length; i++) {
        final book = filteredBooks[i];
        final markerId = MarkerId(book['isbn13'] ?? book['title'] ?? '$i');
        _markers.add(
          Marker(
            markerId: markerId,
            position: LatLng(book['lat'], book['lng']),
            infoWindow: InfoWindow(
              title: book['title'] ?? '',
              onTap: () {
                setState(() {
                  _selectedBook = book;
                });
              },
            ),
            onTap: () {
              setState(() {
                _selectedBook = book;
              });
            },
          ),
        );
        _markerBookMap[markerId] = book;
      }
      // Optionally, add user marker here as well
      _markers.add(
        Marker(
          markerId: MarkerId('user_location'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'You are here'),
        ),
      );
    });
  }

  // Haversine formula to calculate distance between two lat/lng points in miles
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 3958.8; // miles
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _showBookDetails(BuildContext context, Map<String, dynamic> book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _BookDetailsSheet(book: book);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
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
          title: 'Browse',
          onNotificationTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification tapped!')),
            );
          },
          onMenuTap: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_currentPosition == null) {
      return Scaffold(
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
          title: 'Browse',
          onNotificationTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification tapped!')),
            );
          },
          onMenuTap: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        body: Center(child: Text('Could not get current location.')),
      );
    }
    return Scaffold(
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
        title: 'Browse',
        onNotificationTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Notification tapped!')),
          );
        },
        onMenuTap: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition!,
              zoom: 13,
            ),
            myLocationEnabled: true,
            markers: _markers,
            circles: _circles,
            onMapCreated: (controller) {
              _mapController = controller;
              _updateBooksInView(); // Show books in initial view
            },
            onCameraIdle: () {
              _updateBooksInView(); // Update books when user stops moving/zooming the map
            },
          ),
          if (_selectedBook != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: _BookPopOutCard(
                book: _selectedBook!,
                onClose: () => setState(() => _selectedBook = null),
              ),
            ),
        ],
      ),
    );
  }

  double _getZoomLevel(double radiusInMiles) {
    // Approximate formula for zoom level based on radius
    double radiusInMeters = radiusInMiles * 1609.34;
    double scale = radiusInMeters / 500;
    double zoomLevel = 16 - log(scale) / log(2);
    return zoomLevel.clamp(0.0, 21.0);
  }
}

// Add this widget to the same file:
class _BookDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> book;
  const _BookDetailsSheet({required this.book});

  @override
  State<_BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends State<_BookDetailsSheet> {
  bool _showFullDescription = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final imageUrl = book['imageUrl'] as String?;
    final rating = (book['rating'] ?? 0).toDouble();
    final description = book['description'] ?? '';
    final descriptionLines = '\n'.allMatches(description).length + 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (imageUrl != null && imageUrl.isNotEmpty)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    height: 140,
                    width: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            SizedBox(height: 12),
            Text(
              book['title'] ?? 'Book',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (book['author'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('by ${book['author']}', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
              ),
            SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(5, (i) => Icon(
                  i < rating ? Icons.star : Icons.star_border,
                  color: Colors.amber, size: 20,
                )),
                SizedBox(width: 8),
                Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 16)),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Description:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxLines = _showFullDescription ? null : 4;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      maxLines: maxLines,
                      overflow: _showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15),
                    ),
                    if (descriptionLines > 4)
                      GestureDetector(
                        onTap: () => setState(() => _showFullDescription = !_showFullDescription),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            _showFullDescription ? 'Show less' : 'Show more',
                            style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            SizedBox(height: 16),
            Row(
              children: [
                if (book['forRent'] == true)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: Implement rent logic
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Rent request sent!')),
                        );
                      },
                      child: Text('Rent'),
                    ),
                  ),
                if (book['forRent'] == true && book['forBuy'] == true)
                  SizedBox(width: 12),
                if (book['forBuy'] == true)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // TODO: Implement buy logic
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Buy request sent!')),
                        );
                      },
                      child: Text('Buy'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookPopOutCard extends StatefulWidget {
  final Map<String, dynamic> book;
  final VoidCallback onClose;
  const _BookPopOutCard({required this.book, required this.onClose});

  @override
  State<_BookPopOutCard> createState() => _BookPopOutCardState();
}

class _BookPopOutCardState extends State<_BookPopOutCard> {
  bool _showFullDescription = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final imageUrl = book['imageUrl'] as String?;
    final author = book['author'] ?? '';
    final title = book['title'] ?? '';
    final description = book['description'] ?? '';
    final canRent = (book['canRent'] ?? book['forRent']) == true;
    final canBuy = (book['canBuy'] ?? book['forBuy']) == true;
    final isUnavailable = (book['isRented'] == true) || (book['isSold'] == true);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          minHeight: 180,
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black26)],
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            imageUrl,
                            width: 80,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            if (author.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('by $author', style: TextStyle(color: Colors.grey[700], fontSize: 15)),
                              ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                // Thumbs up (actionable)
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
                                // Wishlist (heart icon)
                                WishlistButton(
                                  bookId: book['id'],
                                  bookData: book,
                                ),
                                Spacer(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Description:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  _buildDescription(description),
                  SizedBox(height: 16),
                  Row(
                    children: [
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
                        if (canRent)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookDetailsScreen(book: book, city: book['city'] ?? '', state: book['state'] ?? ''),
                                ),
                              );
                            },
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
                        if (canBuy)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookDetailsScreen(book: book, city: book['city'] ?? '', state: book['state'] ?? ''),
                                ),
                              );
                            },
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
    );
  }

  Widget _buildDescription(String description) {
    final maxLines = _showFullDescription ? null : 3;
    final isLong = description.length > 120 || '\n'.allMatches(description).length > 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          maxLines: maxLines,
          overflow: _showFullDescription ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _showFullDescription = !_showFullDescription),
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                _showFullDescription ? 'Show less' : 'Show more',
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
