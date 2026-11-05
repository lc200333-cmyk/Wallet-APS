import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps Wallet APS typography at its designed size on mobile platforms.
///
/// Android and iOS accessibility text scaling is intentionally disabled for
/// the application UI. Desktop platforms retain their incoming text scaler.
class MobileFixedTextScale extends StatelessWidget {
  const MobileFixedTextScale({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!mobile) return child;
    return MediaQuery.withNoTextScaling(child: child);
  }
}
