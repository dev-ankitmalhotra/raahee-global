import 'package:flutter/material.dart';
import '../utils/wishlist_utils.dart';

class WishlistButton extends StatefulWidget {
  final String bookId;
  final Map<String, dynamic> bookData;

  const WishlistButton({required this.bookId, required this.bookData, Key? key}) : super(key: key);

  @override
  State<WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends State<WishlistButton> {
  bool _isInWishlist = false;

  @override
  void initState() {
    super.initState();
    isInWishlist(widget.bookId).then((value) {
      if (mounted) setState(() => _isInWishlist = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_isInWishlist ? Icons.favorite : Icons.favorite_border, color: Colors.red),
      tooltip: _isInWishlist ? 'Remove from Wishlist' : 'Add to Wishlist',
      onPressed: () async {
        if (_isInWishlist) {
          await removeFromWishlist(widget.bookId);
        } else {
          await addToWishlist(widget.bookId, widget.bookData);
        }
        if (mounted) setState(() => _isInWishlist = !_isInWishlist);
      },
    );
  }
}