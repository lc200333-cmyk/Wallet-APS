import 'package:flutter/material.dart';

/// [darkVeil] darkens a background image (Dark skin); otherwise the image is
/// lightened as in Retro and Light.
BoxDecoration cardSurfaceDecoration({
  required Color color,
  ImageProvider? backgroundImage,
  bool darkVeil = false,
}) =>
    BoxDecoration(
      color: color,
      image: backgroundImage == null
          ? null
          : DecorationImage(
              image: backgroundImage,
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                darkVeil
                    ? Colors.black.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.28),
                BlendMode.srcOver,
              ),
            ),
    );
