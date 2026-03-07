import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Membungkus widget (child) dengan efek Glitch gaya CRT rusak.
/// Efek ini menggeser secara horizontal berulang kali secara random dalam interval sangat singkat.
class GlitchEffect extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final double intensity;

  const GlitchEffect({
    super.key,
    required this.child,
    this.isActive = true,
    this.intensity = 8.0,
  });

  @override
  State<GlitchEffect> createState() => _GlitchEffectState();
}

class _GlitchEffectState extends State<GlitchEffect> {
  Timer? _timer;
  double _horizontalShift = 0.0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startGlitching();
  }

  @override
  void didUpdateWidget(covariant GlitchEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startGlitching();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopGlitching();
    }
  }

  void _startGlitching() {
    // Shift every 60ms
    _timer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (mounted) {
        setState(() {
          // Glitch probability check: 30% chance to glitch per frame
          if (_random.nextDouble() > 0.7) {
            final direction = _random.nextBool() ? 1.0 : -1.0;
            _horizontalShift = _random.nextDouble() * widget.intensity * direction;
          } else {
            _horizontalShift = 0.0;
          }
        });
      }
    });
  }

  void _stopGlitching() {
    _timer?.cancel();
    if (mounted) setState(() => _horizontalShift = 0.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;

    return Transform.translate(
      offset: Offset(_horizontalShift, 0),
      child: widget.child,
    );
  }
}
