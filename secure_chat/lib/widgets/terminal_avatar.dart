// lib/widgets/terminal_avatar.dart
//
// TerminalAvatar — Privacy-safe local avatar widget
// Menggantikan NetworkImage CDN (lh3.googleusercontent.com) dengan
// avatar berbasis inisial nama yang dirender lokal tanpa request jaringan.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TerminalAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? borderColor;
  final Color? accentColor;

  const TerminalAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.borderColor,
    this.accentColor,
  });

  /// Tentukan warna unik berdasarkan hash dari nama (deterministik).
  Color _colorFromName(String n) {
    final hash = n.codeUnits.fold(0, (acc, c) => (acc * 31 + c) & 0xFFFFFF);
    final hue = (hash % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.7, 0.55).toColor();
  }

  /// Ambil 1-2 karakter inisial dari nama.
  String _initialsFromName(String n) {
    final parts = n
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_]'), ' ')
        .trim()
        .split(RegExp(r'[\s_]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromName(name);
    final color = accentColor ?? _colorFromName(name);
    final border = borderColor ?? AppTheme.terminalDim;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: border),
      ),
      child: Stack(
        children: [
          // Subtle grid texture
          CustomPaint(
            size: Size(size, size),
            painter: _GridPainter(color: color),
          ),
          // Initials
          Center(
            child: Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: size * 0.32,
                fontWeight: FontWeight.bold,
                fontFamily: 'IBM Plex Mono',
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a subtle internal grid to give an hacker/terminal aesthetic.
class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;

    final step = math.max(size.width / 4, 4.0);
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
