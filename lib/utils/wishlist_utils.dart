import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> addToWishlist(String bookId, Map<String, dynamic> bookData) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final wishlistRef = FirebaseFirestore.instance.collection('wishlist');

  // Only keep the required attributes
  final filteredData = {
    'userId': user.uid,
    'bookId': bookId,
    'imageUrl': bookData['imageUrl'],
    'author': bookData['author'],
    'category': bookData['category'],
    'isbn13': bookData['isbn13'],
    'title': bookData['title'],
    'canBuy': bookData['canBuy'],
    'canRent': bookData['canRent'],
  };

  await wishlistRef.doc('${user.uid}_$bookId').set(filteredData);
}

Future<void> removeFromWishlist(String bookId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final wishlistRef = FirebaseFirestore.instance.collection('wishlist');
  await wishlistRef.doc('${user.uid}_$bookId').delete();
}

Future<bool> isInWishlist(String bookId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final doc = await FirebaseFirestore.instance
      .collection('wishlist')
      .doc('${user.uid}_$bookId')
      .get();
  return doc.exists;
}