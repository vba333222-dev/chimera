import 'package:flutter/material.dart';

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration typingSpeed;
  final VoidCallback? onFinished;
  final bool isAnimated; // If false, shows text instantly

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 30),
    this.onFinished,
    this.isAnimated = true,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _currentIndex = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAnimated) {
      _startTyping();
    } else {
      _displayedText = widget.text;
      _isFinished = true;
    }
  }

  void _startTyping() async {
    while (_currentIndex < widget.text.length) {
      if (!mounted) return;
      await Future.delayed(widget.typingSpeed);
      setState(() {
        _currentIndex++;
        _displayedText = widget.text.substring(0, _currentIndex);
      });
    }
    setState(() {
      _isFinished = true;
    });
    widget.onFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText + (!_isFinished ? '█' : ''), // Blinking cursor visual during typing
      style: widget.style,
    );
  }
}
