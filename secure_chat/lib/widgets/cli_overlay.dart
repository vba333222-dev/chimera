import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

class CliOverlay extends ConsumerStatefulWidget {
  const CliOverlay({super.key});

  @override
  ConsumerState<CliOverlay> createState() => _CliOverlayState();
}

class _CliOverlayState extends ConsumerState<CliOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  bool _isOpen = false;
  
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  final List<String> _consoleOutput = [
    'Chimera Secure OS v2.4.1',
    'Root access granted.',
    'Type /help for commands.',
    '',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1), // Off-screen top
      end: const Offset(0, 0),    // Fully visible top
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleConsole() {
    HapticFeedback.selectionClick();
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
        _focusNode.requestFocus();
      } else {
        _animationController.reverse();
        _focusNode.unfocus();
        _inputController.clear();
      }
    });
  }

  void _printToConsole(String text) {
    setState(() {
      _consoleOutput.add(text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _processCommand(String cmd) async {
    final command = cmd.trim();
    if (command.isEmpty) return;
    
    _printToConsole('> $command');
    _inputController.clear();

    if (command == '/help') {
      _printToConsole('AVAILABLE COMMANDS:');
      _printToConsole('  /ping [target]   - Check connection latency');
      _printToConsole('  /whoami          - Display current identity profile');
      _printToConsole('  /shred_local_db  - [DANGER] Wipe local message store');
      _printToConsole('  /clear           - Clear console output');
      _printToConsole('  /exit            - Close terminal overlay');
    } else if (command.startsWith('/ping')) {
      final parts = command.split(' ');
      final target = parts.length > 1 ? parts[1] : 'ch-sys-core';
      _printToConsole('Pinging $target...');
      await Future.delayed(const Duration(milliseconds: 600));
      _printToConsole('Reply from $target: time=32ms');
      _printToConsole('Reply from $target: time=29ms');
      _printToConsole('Reply from $target: time=31ms');
    } else if (command == '/whoami') {
      try {
        final identity = ref.read(currentUserIdentityProvider);
        _printToConsole('ID: ${identity.id}');
        _printToConsole('EMAIL: ${identity.email}');
      } catch (e) {
        _printToConsole('ERR: Indentity provider not initialized.');
      }
    } else if (command == '/shred_local_db') {
      _printToConsole('WARNING: Commencing local database wipe...');
      try {
        final db = await ref.read(chatDatabaseProvider.future);
        await db.destroyDatabase();
        await Future.delayed(const Duration(milliseconds: 800));
        _printToConsole('SUCCESS: Local message store irrecoverably shredded.');
      } catch (e) {
        _printToConsole('ERR: Shred failed: $e');
      }
    } else if (command == '/clear') {
      setState(() {
        _consoleOutput.clear();
        _consoleOutput.add('Chimera Secure OS v2.4.1');
      });
    } else if (command == '/exit') {
      _toggleConsole();
    } else {
      _printToConsole('ERR: Command not recognized.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The pull-down tab
        Positioned(
          top: MediaQuery.of(context).padding.top,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta! > 5 && !_isOpen) {
                  _toggleConsole();
                } else if (details.primaryDelta! < -5 && _isOpen) {
                  _toggleConsole();
                }
              },
              onTap: _toggleConsole,
              child: Container(
                width: 60,
                height: 20,
                decoration: BoxDecoration(
                  color: AppTheme.terminalBg.withValues(alpha: 0.9),
                  border: Border.all(color: AppTheme.terminalDim),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Icon(
                  _isOpen ? Icons.keyboard_arrow_up : Icons.terminal,
                  size: 14,
                  color: AppTheme.accentGreen,
                ),
              ),
            ),
          ),
        ),
        
        // The actual terminal overlay
        SlideTransition(
          position: _slideAnimation,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.terminalBg.withValues(alpha: 0.95),
                border: const Border(bottom: BorderSide(color: AppTheme.accentGreen, width: 2)),
                boxShadow: AppTheme.glowGreen,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Terminal output records
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _consoleOutput.length,
                          itemBuilder: (context, index) {
                            return Text(
                              _consoleOutput[index],
                              style: const TextStyle(
                                color: AppTheme.terminalText,
                                fontFamily: 'IBM Plex Mono',
                                fontSize: 12,
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Terminal input line
                      Row(
                        children: [
                          const Text(
                            'root@chimera:~# ',
                            style: TextStyle(
                              color: AppTheme.accentGreenBright,
                              fontFamily: 'IBM Plex Mono',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'IBM Plex Mono',
                                fontSize: 12,
                              ),
                              cursorColor: AppTheme.accentGreen,
                              cursorWidth: 8,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: _processCommand,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
