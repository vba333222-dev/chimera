import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sebuah widget spinner (loading indicator) bergaya murni terminal ASCII.
/// Menggantikan CircularProgressIndicator bawaan Material.
class AsciiSpinner extends StatefulWidget {
  final double fontSize;
  final Color color;
  final String suffixText;
  
  const AsciiSpinner({
    super.key, 
    this.fontSize = 12.0, 
    this.color = AppTheme.accentGreen,
    this.suffixText = '',
  });

  @override
  State<AsciiSpinner> createState() => _AsciiSpinnerState();
}

class _AsciiSpinnerState extends State<AsciiSpinner> {
  static const List<String> _frames = ['/', '-', '\\', '|'];
  int _currentIndex = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _frames.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '[ ${_frames[_currentIndex]} ]',
          style: TextStyle(
            color: widget.color,
            fontSize: widget.fontSize,
            fontFamily: 'IBM Plex Mono',
            fontWeight: FontWeight.bold,
          ),
        ),
        if (widget.suffixText.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            widget.suffixText,
            style: TextStyle(
              color: widget.color,
              fontSize: widget.fontSize,
              fontFamily: 'IBM Plex Mono',
            ),
          ),
        ],
      ],
    );
  }
}
