import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;

  const ChatRoomScreen({Key? key, required this.chatId, required this.chatTitle}) : super(key: key);

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  // A simple flag to show the mock "Screenshot Detected" alert
  bool _showAlert = true;
  final ScrollController _scrollController = ScrollController();

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
                      // Back button
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.terminalCard,
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: const Icon(Icons.lock, size: 16, color: Colors.grey),
                  ),
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
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16).copyWith(bottom: 120),
              children: [
                // Log start marker
                Center(
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
                const SizedBox(height: 16),

                // System Message
                Center(
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
                const SizedBox(height: 24),

                // User 1 Message (Left)
                _buildMessageRow(
                  isSelf: false,
                  initials: 'SC',
                  name: 'Sarah_Chen',
                  time: '09:41:03',
                  message: 'Here are the financials for Q3. Review the attached PDF. Explain variance in col D.',
                ),
                const SizedBox(height: 8),

                // Attachment Message
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: _buildAttachmentMsg(),
                ),
                const SizedBox(height: 24),

                // Security Alert Inject
                Center(
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
                const SizedBox(height: 24),

                // User 2 Message (Right - Self)
                _buildMessageRow(
                  isSelf: true,
                  initials: '',
                  name: '',
                  time: '09:45:12',
                  message: 'Received. Investigating now. Do not forward.',
                ),
                const SizedBox(height: 24),

                // User 1 Message (Left)
                _buildMessageRow(
                  isSelf: false,
                  initials: 'SC',
                  name: 'Sarah_Chen',
                  time: '',
                  message: 'Understood. Terminating secondary session.',
                  hideHeader: true,
                ),
              ],
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
                  // Typing indicator
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 8),
                    child: Row(
                      children: [
                        const Text('> Sarah_Chen is typing', style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(width: 6, height: 12, color: AppTheme.accentGreen), // blinker
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16).copyWith(top: 8),
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
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'IBM Plex Mono'),
                                    decoration: InputDecoration(
                                      hintText: 'ENTER_MESSAGE...',
                                      hintStyle: TextStyle(color: Colors.grey[700]),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Send Button
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.terminalCard,
                            border: Border.all(color: Colors.grey[700]!),
                          ),
                          child: const Icon(Icons.send, color: Colors.grey, size: 18),
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

  Widget _buildMessageRow({
    required bool isSelf,
    required String initials,
    required String name,
    required String time,
    required String message,
    bool hideHeader = false,
  }) {
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
              if (!hideHeader) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSelf) ...[
                      Text(name, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'JetBrains Mono')),
                      const SizedBox(width: 8),
                      Text(time, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'IBM Plex Mono')),
                    ] else ...[
                      const Icon(Icons.lock, size: 12, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(time, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'IBM Plex Mono')),
                    ]
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: isSelf ? Colors.grey[600]! : AppTheme.terminalBorder),
                ),
                child: Text(
                  message,
                  style: TextStyle(color: isSelf ? Colors.white : Colors.grey[200], fontSize: 14, fontFamily: 'IBM Plex Mono', height: 1.5),
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

  Widget _buildAttachmentMsg() {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.terminalCard,
        border: Border.all(color: AppTheme.terminalBorder),
      ),
      child: Row(
        children: [
          Container(width: 2, height: 40, color: AppTheme.accentGreen.withOpacity(0.5)),
          const SizedBox(width: 12),
          const Icon(Icons.description, color: Colors.grey, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Q3_Financials_Conf.pdf', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'IBM Plex Mono'), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('2.4MB', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('|', style: TextStyle(color: Colors.grey[700], fontSize: 10)),
                    ),
                    Text('AES-256', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
