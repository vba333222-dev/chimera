import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

import '../models/message.dart';
import 'dart:async';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatTitle;

  const ChatRoomScreen({Key? key, required this.chatId, required this.chatTitle}) : super(key: key);

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  bool _showAlert = false; // Starts false
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  
  final List<Message> _messages = [
    Message(
      id: 'm1',
      text: 'Here are the financials for Q3. Review the attached PDF. Explain variance in col D.',
      senderId: 'SC',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    Message(
      id: 'm2',
      text: 'Received. Investigating now. Do not forward.',
      senderId: 'ME',
      timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    Message(
      id: 'm3',
      text: 'Understood. Terminating secondary session.',
      senderId: 'SC',
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    )
  ];

  void _sendMessage() {
    if (_textController.text.trim().isEmpty) return;
    
    final text = _textController.text;
    
    setState(() {
      _messages.add(
        Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          senderId: 'ME',
          timestamp: DateTime.now(),
        )
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
    _initScreenProtector();
    _startTyping();
    _initWebSocket();
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
    }, (ScreenshotEvent event) {}); // No iOS specific event handling needed for basic mock
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
          // Main Chat Area
          Positioned.fill(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16).copyWith(bottom: 120),
              itemCount: _messages.length + 3, // +3 for header, system message, and alert
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildLogStartMarker();
                } else if (index == 1) {
                  return _buildSystemMessage();
                } else if (index == 2) {
                  return _buildSecurityAlert();
                }
                
                final msgIndex = index - 3;
                final message = _messages[msgIndex];
                final isSelf = message.senderId == 'ME';
                final isLastMessage = msgIndex == _messages.length - 1;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildMessageRow(
                    message: message,
                    isSelf: isSelf,
                    animate: !isSelf && isLastMessage && message.timestamp.difference(DateTime.now()).abs() < const Duration(seconds: 5),
                  ),
                );
              },
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

  Widget _buildLogStartMarker() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
              ),
              child: Text('2023-10-24 [LOG_START]', style: AppTheme.darkTheme.textTheme.labelSmall?.copyWith(letterSpacing: 2, color: Colors.grey[600])),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person, size: 10, color: Colors.grey),
                const SizedBox(width: 4),
                Text('E2EE_ACTIVE // ZERO_TRUST_NODE', style: TextStyle(fontSize: 9, fontFamily: 'IBM Plex Mono', letterSpacing: 2, color: Colors.grey[600])),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSystemMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.terminalCard,
            border: Border.all(color: AppTheme.terminalBorder),
          ),
          width: MediaQuery.of(context).size.width * 0.9,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 12),
                child: Icon(Icons.terminal, color: AppTheme.accentGreen, size: 16),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('> SYSTEM_ROOT', style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
                    const SizedBox(height: 4),
                    Text('Handshake complete. Identity verified (RSA-4096). Session is strictly confidential.',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12, fontFamily: 'IBM Plex Mono', height: 1.5)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityAlert() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber.withOpacity(0.05),
            border: Border.all(color: AppTheme.warningAmber),
            boxShadow: [
              BoxShadow(color: AppTheme.warningAmber.withOpacity(0.1), blurRadius: 10)
            ],
          ),
          width: MediaQuery.of(context).size.width * 0.9,
          child: Row(
            children: [
              const Icon(Icons.key_off, color: AppTheme.warningAmber, size: 18),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SECURITY ALERT', style: TextStyle(color: AppTheme.warningAmber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text("User 'J.Doe' keys changed. Verify fingerprint.", style: TextStyle(color: AppTheme.warningAmber.withOpacity(0.8), fontSize: 10, fontFamily: 'IBM Plex Mono')),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageRow({
    required Message message,
    required bool isSelf,
    bool animate = false,
  }) {
    final initials = isSelf ? '' : (message.senderId.length >= 2 ? message.senderId.substring(0, 2) : '??');
    final name = isSelf ? 'ME' : 'Sarah_Chen'; // Hardcoded for demo
    final timeStr = "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";

    return Row(
      mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isSelf) ...[
          Container(
            width: 32,
            height: 32,
            color: Colors.grey[800],
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[600]!),
            ),
            alignment: Alignment.center,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'IBM Plex Mono')),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isSelf) ...[
                    Text(name, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
                    const SizedBox(width: 8),
                    Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'IBM Plex Mono')),
                  ] else ...[
                    const Icon(Icons.lock, size: 12, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(timeStr, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'IBM Plex Mono')),
                  ]
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: isSelf ? AppTheme.accentGreen.withOpacity(0.5) : AppTheme.terminalBorder),
                ),
                child: animate ? _TypewriterText(text: message.text, isSelf: isSelf) : Text(
                  message.text,
                  style: TextStyle(color: isSelf ? AppTheme.accentGreenBright : Colors.grey[200], fontSize: 14, fontFamily: 'IBM Plex Mono', height: 1.5),
                ),
              ),
              if (isSelf) ...[
                const SizedBox(height: 4),
                const Icon(Icons.check, color: AppTheme.accentGreen, size: 14),
              ]
            ],
          ),
        ),
      ],
    );
  }
}

class _TypewriterText extends StatefulWidget {
  final String text;
  final bool isSelf;
  const _TypewriterText({Key? key, required this.text, required this.isSelf}) : super(key: key);

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayedText = '';
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_currentIndex < widget.text.length) {
        setState(() {
          _displayedText += widget.text[_currentIndex];
          _currentIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText + (_currentIndex < widget.text.length ? '█' : ''),
      style: TextStyle(color: widget.isSelf ? AppTheme.accentGreenBright : Colors.grey[200], fontSize: 14, fontFamily: 'IBM Plex Mono', height: 1.5),
    );
  }
}

class _AnimatedShield extends StatefulWidget {
  const _AnimatedShield({Key? key}) : super(key: key);

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
            color: _isSecure ? AppTheme.accentGreen.withOpacity(0.1) : Colors.transparent,
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


