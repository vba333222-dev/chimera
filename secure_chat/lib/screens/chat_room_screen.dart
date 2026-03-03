import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import '../models/message.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_message_list.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatTitle;

  const ChatRoomScreen({super.key, required this.chatId, required this.chatTitle});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  bool _showAlert = false; // Starts false
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  
  // Demo messages — sessionId akan diisi dari widget.chatId saat initState
  final List<Message> _messages = [];

  void _sendMessage() {
    if (_textController.text.trim().isEmpty) return;
    
    final text = _textController.text;
    
    setState(() {
      _messages.add(
        Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: widget.chatId,
          text: text,
          senderId: 'ME',
          timestamp: DateTime.now(),
        ),
      );
      _textController.clear();
    });
    
    _scrollToBottom();
    
    // Send to WebSocket
    ref.read(webSocketServiceProvider).sendMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initDemoMessages();
    _initScreenProtector();
    _initWebSocket();
  }

  void _initDemoMessages() {
    // Populate demo messages menggunakan sessionId dari route parameter
    _messages.addAll([
      Message(
        id: 'm1',
        sessionId: widget.chatId,
        text: 'Here are the financials for Q3. Review the attached PDF. Explain variance in col D.',
        senderId: 'SC',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      Message(
        id: 'm2',
        sessionId: widget.chatId,
        text: 'Received. Investigating now. Do not forward.',
        senderId: 'ME',
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      Message(
        id: 'm3',
        sessionId: widget.chatId,
        text: 'Understood. Terminating secondary session.',
        senderId: 'SC',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);
  }
  
  void _initWebSocket() {
    final wsService = ref.read(webSocketServiceProvider);
    
    // In a real app, URL comes from env or config
    wsService.connect('wss://echo.websocket.events');
    
    wsService.messageStream.listen((message) {
      if (mounted) {
        setState(() {
          _messages.add(message);
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _initScreenProtector() async {
    // Prevent screenshot and screen recording
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageOn();
    
    // Listen for attempted screenshots
    ScreenProtector.addListener(() {
      if (mounted) {
        setState(() {
          _showAlert = true;
        });
        // Auto-hide alert after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && _showAlert) {
            setState(() {
              _showAlert = false;
            });
          }
        });
      }
    }, (dynamic event) {}); // No iOS specific event handling needed for basic mock
  }

  @override
  void dispose() {
    ScreenProtector.removeListener();
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Uses PixelGrid from main
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.terminalBg,
            border: Border(bottom: BorderSide(color: AppTheme.terminalBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.terminalCard,
                          border: Border.all(color: AppTheme.terminalBorder),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_back, size: 16, color: AppTheme.terminalText),
                          onPressed: () => context.pop(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(widget.chatTitle, style: AppTheme.darkTheme.textTheme.titleSmall?.copyWith(letterSpacing: 2)),
                              const SizedBox(width: 8),
                              Container(width: 8, height: 8, color: AppTheme.accentGreen), // Simulated pulse
                            ],
                          ),
                          Text('ID: CH-2901-SEC', style: AppTheme.darkTheme.textTheme.labelSmall?.copyWith(color: Colors.grey[500], letterSpacing: 2)),
                        ],
                      )
                    ],
                  ),
                  const _AnimatedShield(),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── Main Chat Area (Optimized) ─────────────────────────────────
          // Menggunakan OptimizedMessageList dengan:
          //   • findChildIndexCallback: O(1) lookup via ValueKey(message.id)
          //   • RepaintBoundary per item: isolasi layer compositing
          //   • AutomaticKeepAlive: preserve state saat scroll off-screen
          //   • Const header widgets: zero rebuild untuk LogMarker, SystemMsg
          //   • cacheExtent=500: pre-render 500px di luar viewport
          Positioned.fill(
            child: OptimizedMessageList(
              messages: _messages,
              scrollController: _scrollController,
              localUserId: 'ME',
            ),
          ),

          // Screenshot Alert overlay at the top (disappears if clicked)
          if (_showAlert)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.warningRed,
                  border: Border.all(color: Colors.red[900]!, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('ALERT: SCREENSHOT DETECTED', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1, fontFamily: 'JetBrains Mono')),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showAlert = false),
                      child: const Icon(Icons.close, color: Colors.white70, size: 18),
                    )
                  ],
                ),
              ),
            ),

          // Bottom Input Area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.terminalBg,
                border: Border(top: BorderSide(color: AppTheme.terminalBorder)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16).copyWith(top: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Add Button
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.transparent),
                          ),
                          child: const Icon(Icons.add, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        // Input Box
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.terminalBg,
                              border: Border.all(color: AppTheme.terminalBorder),
                            ),
                            child: Row(
                              children: [
                                const Text('>', style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _textController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'IBM Plex Mono'),
                                    decoration: InputDecoration(
                                      hintText: 'ENTER_MESSAGE...',
                                      hintStyle: TextStyle(color: Colors.grey[700]),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Send Button
                        InkWell(
                          onTap: _sendMessage,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.terminalCard,
                              border: Border.all(color: Colors.grey[700]!),
                            ),
                            child: const Icon(Icons.send, color: Colors.grey, size: 18),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

}


class _AnimatedShield extends StatefulWidget {
  const _AnimatedShield();

  @override
  State<_AnimatedShield> createState() => _AnimatedShieldState();
}

class _AnimatedShieldState extends State<_AnimatedShield> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSecure = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    // Simulate key handshake process
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isSecure = true;
        });
        _controller.stop();
        _controller.value = 1.0;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final color = _isSecure 
            ? AppTheme.accentGreen 
            : Color.lerp(Colors.grey[700], AppTheme.warningAmber, _controller.value);
            
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isSecure ? AppTheme.accentGreen.withValues(alpha: 0.1) : Colors.transparent,
            border: Border.all(color: color ?? AppTheme.terminalBorder),
            boxShadow: _isSecure ? AppTheme.glowGreen : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSecure ? Icons.security : Icons.sync_lock,
                size: 14,
                color: color,
              ),
              if (_isSecure) ...[
                const SizedBox(width: 6),
                Text(
                  'E2EE: SECURE',
                  style: const TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                )
              ]
            ],
          ),
        );
      },
    );
  }
}


