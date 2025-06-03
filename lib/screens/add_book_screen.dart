import 'package:flutter/material.dart';
import 'package:raahee_global_book_library/widgets/generic_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../main.dart';

class AddBookScreen extends StatefulWidget {
  @override
  _AddBookScreenState createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  File? _image;
  final picker = ImagePicker();
  bool isLoading = false;
  bool detailsFetched = false;

  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _industryIdentifiersController = TextEditingController();
  final _ratingController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _rentPriceController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _retailPriceController = TextEditingController();

  bool canRent = false;
  bool canBuy = false;

  bool _isDescriptionExpanded = false;

  String _bookCondition = 'Good';
  double _recommendedPrice = 0.0;

  double? _fetchedRetailPrice;
  String? _fetchedCurrencyCode;

  Future<void> _pickImage() async {
    XFile? pickedFile;

    try {
      if (kIsWeb) {
        pickedFile = await picker.pickImage(source: ImageSource.camera);
      } else {
        if (Platform.isAndroid || Platform.isIOS) {
          pickedFile = await picker.pickImage(source: ImageSource.camera);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Camera not supported on this platform.")),
          );
          return;
        }
      }

      if (pickedFile != null) {
        print('Picked file path: ${pickedFile.path}');
        setState(() {
          if (!kIsWeb) {
            _image = File(pickedFile!.path);
          }
          isLoading = true;
        });

        String extractedTitle = '';
        if (!kIsWeb && _image != null) {
          print('Image path: ${_image!.path}');
          print('Extracting title from image...');
          extractedTitle = await extractTitleFromImage(_image!);
        } else if (kIsWeb) {
          // Prompt user for title on web
          extractedTitle = await showDialog<String>(
            context: context,
            builder: (context) {
              final controller = TextEditingController();
              return AlertDialog(
                title: Text('Enter Book Title'),
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: 'Book Title'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: Text('OK'),
                  ),
                ],
              );
            },
          ) ?? '';
        }

        await _fetchBookDetails(query: extractedTitle.isNotEmpty ? extractedTitle : 'moby dick');
        setState(() {
          isLoading = false;
          detailsFetched = true;
        });
      } else {
        print('No image was picked.');
      }
    } catch (e) {
      print("Image picking error: $e");
    }
  }

  Future<void> _fetchBookDetails({required String query}) async {
    final url = Uri.parse('https://www.googleapis.com/books/v1/volumes?q=$query');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['items'] != null && data['items'].isNotEmpty) {
        final book = data['items'][0]['volumeInfo'];
        final saleInfo = data['items'][0]['saleInfo'];

        // Extract ISBN_13 identifier
        String isbn13 = '';
        if (book['industryIdentifiers'] != null) {
          for (var id in book['industryIdentifiers']) {
            if (id['type'] == 'ISBN_13') {
              isbn13 = id['identifier'];
              break;
            }
          }
        }

        setState(() {
          _titleController.text = book['title'] ?? '';
          _authorController.text = (book['authors'] ?? ['']).join(', ');
          _categoryController.text = (book['categories'] ?? [''])[0];
          _descriptionController.text = book['description'] ?? '';
          _industryIdentifiersController.text = isbn13; // <-- Store ISBN_13 here
          _ratingController.text = book['averageRating']?.toString() ?? '';
          var imgUrl = book['imageLinks']?['thumbnail'] ?? '';
          if (imgUrl.startsWith('http://')) {
            imgUrl = imgUrl.replaceFirst('http://', 'https://');
          }
          _imageUrlController.text = imgUrl;

          // Set fetched retail price and currency
          _fetchedRetailPrice = saleInfo?['retailPrice']?['amount']?.toDouble();
          _fetchedCurrencyCode = saleInfo?['retailPrice']?['currencyCode'];
        });
      }
    }
  }

  Future<void> _submitBook() async {
    print('Post Book Listing button pressed');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch city and state
    final location = await getLocationFromIP();

    // 1. Generate a new document reference to get a unique ID
    final docRef = FirebaseFirestore.instance.collection('books').doc();
    final String bookId = docRef.id;

    // 2. Add the generated ID to your bookData
    // Build search_keywords array from title and author
    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final searchKeywords = <String>{
      ...title.toLowerCase().split(RegExp(r'\s+')),
      ...author.toLowerCase().split(RegExp(r'\s+')),
    }..removeWhere((s) => s.isEmpty);

    final bookData = {
      'id': bookId, // <-- Add this line
      'title': title,
      'author': author,
      'category': _categoryController.text,
      'description': _descriptionController.text,
      'rating': double.tryParse(_ratingController.text) ?? 0.0,
      'imageUrl': _imageUrlController.text,
      'rentPrice': double.tryParse(_rentPriceController.text) ?? 0.0,
      'buyPrice': double.tryParse(_buyPriceController.text) ?? 0.0,
      'canRent': canRent,
      'canBuy': canBuy,
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'city': location['city'],
      'state': location['state'],
      'lat': location['lat'],
      'lng': location['lng'],
      'isbn13': _industryIdentifiersController.text,
      'isRented': false,
      'isSold': false,
      'search_keywords': searchKeywords.toList(), // <-- Add this line
    };
    print('Book data: $bookData');
    print('pre database call');

    // 3. Save the document using .set() with the generated ID
    await docRef.set(bookData);

    print('Post database call');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Book listed successfully!')));
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Future<String> extractTitleFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

    print('OCR result: ${recognizedText.text}'); // <-- Add this line

    // Simple heuristic: use the first non-empty line as the title
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty && text.length > 2) {
          print('Extracted title candidate: $text'); // <-- Add this line
          return text;
        }
      }
    }
    return '';
  }

  Future<Map<String, dynamic>> getLocationFromIP() async {
    try {
      print('Fetching location data...');
      final response = await http.get(Uri.parse('https://ipinfo.io/json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Location data: $data');
        double? lat;
        double? lng;
        if (data['loc'] != null) {
          final parts = (data['loc'] as String).split(',');
          if (parts.length == 2) {
            lat = double.tryParse(parts[0]);
            lng = double.tryParse(parts[1]);
          }
        }
        return {
          'city': data['city'] ?? '',
          'state': data['region'] ?? '',
          'lat': lat,
          'lng': lng,
        };
      }
    } catch (e) {
      print('Location fetch error: $e');
    }
    return {'city': '', 'state': '', 'lat': null, 'lng': null};
  }

  void _updateRecommendedPrice() {
    // Use fetched retail price if available, else use user input
    final retail = _fetchedRetailPrice ?? double.tryParse(_retailPriceController.text) ?? 0.0;
    double reduction = 0.4; // Default for 'Good'
    if (_bookCondition == 'Fair') reduction = 0.5;
    if (_bookCondition == 'Excellent') reduction = 0.3;

    setState(() {
      // Only calculate if retail price is available and a condition is selected
      if (retail > 0 && _bookCondition.isNotEmpty) {
        _recommendedPrice = retail * (1 - reduction);
        _buyPriceController.text = _recommendedPrice.toStringAsFixed(2);
      } else {
        _recommendedPrice = 0.0;
        _buyPriceController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the button should be enabled
    bool isRentValid = canRent && _rentPriceController.text.trim().isNotEmpty;
    bool isBuyValid = canBuy && _buyPriceController.text.trim().isNotEmpty;
    bool isButtonEnabled = (canRent || canBuy) && (isRentValid || isBuyValid);

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
        title: 'Add Book',
        onNotificationTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Notification tapped!')),
          );
        },
        onMenuTap: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!detailsFetched) ...[
                    SizedBox(height: 80),
                    Center(child: Icon(Icons.camera_alt, size: 100, color: Colors.grey)),
                    SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.camera_alt),
                        label: Text('Scan Book Cover'),
                        onPressed: _pickImage,
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.camera_alt),
                        label: Text('Rescan Book Cover'),
                        onPressed: _pickImage,
                      ),
                    ),
                    SizedBox(height: 24),
                    // Book preview layout similar to Book Details Screen
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Book cover (network or file or placeholder)
                        Container(
                          height: 180,
                          width: 130,
                          color: Colors.deepOrange.shade200,
                          child: Builder(
                            builder: (_) {
                              final url = _imageUrlController.text;
                              if (url.isNotEmpty && url.startsWith('https://')) {
                                return Image.network(
                                  url,
                                  height: 180,
                                  width: 130,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    if (_image != null && !kIsWeb) {
                                      return Image.file(_image!, height: 180, width: 130, fit: BoxFit.cover);
                                    }
                                    return Icon(Icons.broken_image, size: 64, color: Colors.grey);
                                  },
                                );
                              } else if (_image != null && !kIsWeb) {
                                return Image.file(_image!, height: 180, width: 130, fit: BoxFit.cover);
                              }
                              return Icon(Icons.camera_alt, size: 64, color: Colors.white70);
                            },
                          ),
                        ),
                        SizedBox(width: 24),
                        // Book info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titleController.text.isNotEmpty ? _titleController.text : 'No Title',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 10),
                              if (_categoryController.text.isNotEmpty)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _categoryController.text,
                                    style: TextStyle(fontSize: 16, color: Colors.deepOrange),
                                  ),
                                ),
                              SizedBox(height: 10),
                              Text('Author: ${_authorController.text.isNotEmpty ? _authorController.text : "Unknown"}',
                                  style: TextStyle(fontSize: 18)),
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.star, color: Colors.amber, size: 22),
                                  SizedBox(width: 6),
                                  Text(_ratingController.text.isNotEmpty ? _ratingController.text : "0.0",
                                      style: TextStyle(fontSize: 18)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                          child: Text(
                            _descriptionController.text.isNotEmpty
                                ? _descriptionController.text
                                : "No description available.",
                            style: TextStyle(fontSize: 16),
                            maxLines: _isDescriptionExpanded ? null : 4,
                            overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                          ),
                        ),
                        if (_descriptionController.text.length > 100) // Show button only if description is long
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _isDescriptionExpanded = !_isDescriptionExpanded;
                                });
                              },
                              child: Text(_isDescriptionExpanded ? 'Show less' : 'Show more'),
                            ),
                          ),
                      ],
                    ),
                    // Editable fields
                    // TextField(controller: _titleController, decoration: InputDecoration(labelText: 'Title')),
                    // TextField(controller: _authorController, decoration: InputDecoration(labelText: 'Author')),
                    // TextField(controller: _categoryController, decoration: InputDecoration(labelText: 'Category')),
                    // TextField(controller: _ratingController, decoration: InputDecoration(labelText: 'Rating')),
                    // TextField(
                    //   controller: _descriptionController,
                    //   decoration: InputDecoration(labelText: 'Description'),
                    // ),
                    
                    SwitchListTile(
                      title: Text('Available for Rent'),
                      value: canRent,
                      onChanged: (val) {
                        setState(() {
                          canRent = val;
                          if (canRent && _rentPriceController.text.trim().isEmpty) {
                            _rentPriceController.text = '0.99'; // Default rental price
                          }
                          if (!canRent) {
                            _rentPriceController.clear();
                          }
                        });
                      },
                    ),
                    if (canRent)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Rent Price: \$${_rentPriceController.text.isNotEmpty ? _rentPriceController.text : "0.99"} /week',
                          style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                        ),
                      ),
                    SwitchListTile(
                      title: Text('Available for Purchase'),
                      value: canBuy,
                      onChanged: (val) {
                        setState(() {
                          canBuy = val;
                          if (!canBuy) {
                            _buyPriceController.clear();
                            _retailPriceController.clear();
                            _recommendedPrice = 0.0;
                          }
                        });
                      },
                    ),
                    if (canBuy) ...[
                      // TextField(
                      //   controller: _retailPriceController,
                      //   decoration: InputDecoration(labelText: 'Retail Price (\$)'),
                      //   keyboardType: TextInputType.number,
                      //   onChanged: (_) => _updateRecommendedPrice(),
                      // ),
                      SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _bookCondition,
                        items: ['Fair', 'Good', 'Excellent']
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _bookCondition = val;
                            });
                            _updateRecommendedPrice();
                          }
                        },
                        decoration: InputDecoration(labelText: 'Book Condition'),
                      ),
                      SizedBox(height: 10),
                      if (_recommendedPrice > 0) ...[
                        // Text(
                        //   'Recommended Price: \$${_recommendedPrice.toStringAsFixed(2)}',
                        //   style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                        // ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Your Price: \$${_recommendedPrice.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                          ),
                        ),
                      ],
                      // TextField(
                      //   controller: _buyPriceController,
                      //   decoration: InputDecoration(labelText: 'Your Price (\$)'),
                      //   keyboardType: TextInputType.number,
                      // ),
                    ],
                    SizedBox(height: 20),
                    if (_fetchedRetailPrice != null && _fetchedCurrencyCode != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Retail Price (from Google): ${_fetchedCurrencyCode!} ${_fetchedRetailPrice!.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: isButtonEnabled ? _submitBook : null,
                      child: Text('Post Book Listing'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
