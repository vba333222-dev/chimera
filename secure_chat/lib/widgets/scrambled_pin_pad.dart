import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ScrambledPinPad extends StatefulWidget {
  final ValueChanged<String> onKeyPress;
  final bool scrambleOnTouch;

  const ScrambledPinPad({
    super.key,
    required this.onKeyPress,
    this.scrambleOnTouch = true,
  });

  @override
  State<ScrambledPinPad> createState() => _ScrambledPinPadState();
}

class _ScrambledPinPadState extends State<ScrambledPinPad> {
  // Posisi 10 angka dinamis (0-9)
  late List<String> _numbers;

  @override
  void initState() {
    super.initState();
    _shuffleNumbers();
  }

  void _shuffleNumbers() {
    _numbers = List.generate(10, (index) => index.toString());
    _numbers.shuffle(Random.secure());
  }

  void _handleKeyPress(String key) {
    widget.onKeyPress(key);
    // Acak ulang jika scrambleOnTouch aktif dan kunci yang ditekan bukan DEL/ENT
    // (Bisa juga diubah selalu acak tanpa peduli apa yang ditekan, tapi UX-wise 
    // jika user tekan DEL mungkin dia salah tekan dan butuh posisi yang agak familiar walau sekilas.
    // Namun untuk anti-shoulder surfing absolut, kita selalu acak di setiap sentuhan pada tombol angka).
    if (widget.scrambleOnTouch && key != 'DEL' && key != 'ENT') {
      setState(() {
        _shuffleNumbers();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 12,
        itemBuilder: (context, index) {
          String key;
          
          // Layout Grid 3x4:
          // 0 1 2
          // 3 4 5
          // 6 7 8
          // 9 10 11 (9: DEL, 10: Angka sisa, 11: ENT)

          if (index < 9) {
            key = _numbers[index];
          } else if (index == 9) {
            key = 'DEL';
          } else if (index == 10) {
            key = _numbers[9]; // Angka terakhir ditaruh di tengah bawah
          } else {
            key = 'ENT';
          }

          return _KeypadButton(
            label: key,
            onTap: () => _handleKeyPress(key),
          );
        },
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeypadButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isAction = label == 'DEL' || label == 'ENT';
    
    return InkWell(
      onTap: onTap,
      splashColor: AppTheme.accentGreen.withValues(alpha: 0.3),
      highlightColor: AppTheme.accentGreen.withValues(alpha: 0.1),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.terminalCard,
          border: Border.all(
            color: isAction 
                ? AppTheme.terminalBorder 
                : AppTheme.accentGreen.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: !isAction ? [
            BoxShadow(
              color: AppTheme.accentGreen.withValues(alpha: 0.1),
              blurRadius: 4,
              spreadRadius: 1,
            )
          ] : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isAction ? Colors.white : AppTheme.accentGreen,
            fontSize: isAction ? 14 : 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrains Mono', // Gunakan font monospace supaya mirip terminal/industri
            letterSpacing: isAction ? 1.5 : null,
          ),
        ),
      ),
    );
  }
}
