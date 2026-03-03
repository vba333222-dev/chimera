import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TerminalContainer extends StatelessWidget {
  final Widget child;
  final bool isAlert;
  final bool isInteractive;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const TerminalContainer({
    super.key,
    required this.child,
    this.isAlert = false,
    this.isInteractive = false,
    this.padding = const EdgeInsets.all(12.0),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.terminalCard,
        border: Border.all(
          color: isAlert ? AppTheme.warningRed : AppTheme.terminalBorder,
        ),
        boxShadow: isInteractive
            ? (isAlert ? AppTheme.glowRed : AppTheme.glowGreen)
            : null,
      ),
      child: child,
    );
  }
}
