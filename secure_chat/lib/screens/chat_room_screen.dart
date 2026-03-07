import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import '../env/env.dart';
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
  bool _showAlert = false;
  bool _isInitializing = true;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];

  // ── PFS state ─────────────────────────────────────────────────────────────
  /// True setelah PFS session berhasil diinisialisasi.
  bool _pfsReady = false;

  /// Epoch saat ini (hanya untuk ditampilkan di UI debug — bisa dihapus di prod).
  int _pfsEpoch = 0;

  bool _showCommandMenu = false;

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openDemoDocument() async {
    // 1. Simulasi menerima & mendekripsi buffer file rahasia
    final dummyBytes = Uint8List.fromList('SECURE_PAYLOAD_DUMMY_IMAGE'.codeUnits);
    
    // 2. Berikan ke SecureDocumentService untuk didekrip (pure Memory)
    final memoryBytes = await ref.read(secureDocumentServiceProvider).decryptDocumentInMemory(dummyBytes);
    
    // 3. Buka Document Viewer (Via Memory Data Object)
    if (mounted) {
      context.push('/viewer?isPdf=false', extra: memoryBytes);
    }
  }

  Future<void> _sendEphemeralText() async {
    HapticFeedback.lightImpact();
    if (_textController.text.trim().isEmpty) return;
    
    final text = _textController.text;
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    // Set expiry 10 seconds from now
    final expires = DateTime.now().add(const Duration(seconds: 10));

    final msg = Message(
      id: msgId,
      sessionId: widget.chatId,
      text: text,
      senderId: 'ME',
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      expiresAt: expires,
    );

    setState(() {
      _messages.add(msg);
      _textController.clear();
    });
    _scrollToBottom();
    
    final db = await ref.read(chatDatabaseProvider.future);
    await db.insertMessage(msg);
  }

  Future<void> _sendViewOnceMedia() async {
    HapticFeedback.lightImpact();
    // Mock Payload for View-Once Media
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final expires = DateTime.now().add(const Duration(hours: 1)); // TTL just in case it is ignored

    final msg = Message(
      id: msgId,
      sessionId: widget.chatId,
      text: 'SECURE_PAYLOAD: IN_MEMORY_ATTACHMENT',
      senderId: 'ME',
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      expiresAt: expires,
    );

    setState(() {
      _messages.add(msg);
      _textController.clear();
    });
    _scrollToBottom();
    
    final db = await ref.read(chatDatabaseProvider.future);
    await db.insertMessage(msg);
  }

  Future<void> _sendStegoPayload() async {
    HapticFeedback.lightImpact();
    
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Create the stego message
    final msg = Message(
      id: msgId,
      sessionId: widget.chatId,
      text: '[STEG-ENC] Payload hidden in LSB of attached image',
      senderId: 'ME',
      timestamp: DateTime.now(),
      status: MessageStatus.pending,
    );

    setState(() {
      _messages.add(msg);
    });
    _scrollToBottom();
    
    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 1200));
    
    final db = await ref.read(chatDatabaseProvider.future);
    final sentMsg = msg.copyWith(status: MessageStatus.sent);
    await db.insertMessage(sentMsg);
    
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) _messages[idx] = sentMsg;
      });
    }
  }

  Future<void> _simulateRemoteKillSwitch() async {
    // 1. Dapatkan websocket service
    final wsService = ref.read(webSocketServiceProvider);
    
    // 2. Tembakkan raw payload khusus ke websocket yang diterima server
    // (Namun karena server dummy ini sekadar mengembalikan echo,
    // interceptor di WebSocketService akan menangkap echo-nya sendiri).
    // Lebih gampang kita langsung feed JSON payload ke sink untuk verifikasi:
    
    final payload = '{"type":"SYS_COMMAND", "action":"KILL_SWITCH"}';
    wsService.sendMessage(payload);

    // Karena wsService dummy kita mungkin tidak meng-echo payload JSON
    // jika kita sedang tidak konek, untuk tujuan simulasi tes Task 22 kita
    // akan feed payload ini langsung kalau tidak connect.
    if (!wsService.isConnected) {
       // Manual injeksi ke interceptor
       final Map<String, dynamic> jsonMap = jsonDecode(payload);
       if (jsonMap['type'] == 'SYS_COMMAND' && jsonMap['action'] == 'KILL_SWITCH') {
          ref.read(selfDestructServiceProvider).executeSelfDestruct();
          ref.read(securityThreatProvider.notifier).reportThreat(ThreatType.remoteKillSwitch);
       }
    }
  }

  /// Kirim pesan (dimasukkan ke Offline Queue).
  ///
  /// Alur:
  ///   1. Buat message dengan status `pending` (atau `sent` jika fallback demo)
  ///   2. Jika PFS belum siap, tambah ke UI saja (simulasi).
  ///   3. Jika PFS siap, enkripsi dengan session key epoch saat ini via Isolate.
  ///   4. Simpan ke database lokal menggunakan ChatDatabaseService.
  ///   5. Tambah ke UI (optimistic update).
  ///   6. OfflineQueueService akan otomatis mendeteksi DB "pending" dan 
  ///      mengirimkannya ke WebSocket di background.
  Future<void> _sendMessage() async {
    HapticFeedback.lightImpact();
    if (_textController.text.trim().isEmpty) return;


    final text = _textController.text;
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();

    // Optimistic UI update — pesan muncul langsung tanpa menunggu enkripsi
    setState(() {
      _messages.add(Message(
        id: msgId,
        sessionId: widget.chatId,
        text: text,
        senderId: 'ME',
        timestamp: DateTime.now(),
      ));
      _textController.clear();
    });
    _scrollToBottom();

    // Enkripsi + simpan ke DB sebagai pending message
    if (_pfsReady) {
      try {
        final pfsService = ref.read(pfsSessionServiceProvider);
        
        // Peringatan: Saat ini _sendMessage kita mengenkripsi dan langsung 
        // memasukkan JSON packet sebagai "text" pesan ke DB untuk dikirim raw
        // oleh OfflineQueueService. Pada arsitektur ideal, DB menyimpan plaintext, 
        // dan worker (offline_queue_service) yang mengenkripsi ulang menggunakan
        // key PFS *terbaru* persis sebelum pengiriman. 
        // Untuk demo phase ini sesuai PRD, kita simpan text yang akan dikirim.
        
        final packet = await pfsService.encryptForSession(widget.chatId, text);

        // Update epoch indicator di UI jika berubah
        if (pfsService.currentEpoch(widget.chatId) != _pfsEpoch) {
          setState(() => _pfsEpoch = pfsService.currentEpoch(widget.chatId));
        }

        // Teks untuk dikirim adalah JSON string dari packet
        final textToSend = packet.toJson();

        final msgToDb = Message(
          id: msgId,
          sessionId: widget.chatId,
          text: textToSend,
          senderId: 'ME',
          timestamp: DateTime.now(),
          status: MessageStatus.pending, // Tandai pending masuk antrean
        );

        final db = await ref.read(chatDatabaseProvider.future);
        await db.insertMessage(msgToDb);
        
        // Panggil offline queue processor (meskipun otomatis juga mendengarkan stream)
        ref.read(offlineQueueServiceProvider).processQueue();

      } catch (e) {
        // ignore: avoid_print
        print('[PFS] Encryption error: $e');
        // Fallback: biarkan UI render saja (plaintext) — tidak simpan DB
      }
    } else {
      // PFS belum siap — abaikan penyimpanan DB (hanya tampil di UI untuk demo)
      // ignore: avoid_print
      print('[PFS] Not ready. Message not stored in queue.');
    }
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
    
    _initDemoMessages();
    _initWebSocket(); // juga menginisialisasi PFS
  }

  void _initDemoMessages() {
    // Demo dinonaktifkan as default untuk melihat status empty & skeleton.
    // Jika perlu message statis, bisa dilepas komennya.
    /*
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
    */
  }
  
  /// Inisialisasi WebSocket + PFS session dengan X3DH handshake nyata.
  ///
  /// Alur:
  ///   1. Pastikan prekey bundle lokal sudah ter-publish (generate jika perlu).
  ///   2. Lakukan X3DH dengan peer (chatId = peerId) untuk mendapat shared secret.
  ///   3. Gunakan shared secret sebagai seed PFS session (gantikan dummy key nol).
  ///   4. Koneksi WebSocket + listen pesan masuk.
  Future<void> _initWebSocket() async {
    // ── Phase 8: X3DH Handshake ─────────────────────────────────────────────
    final x3dh = ref.read(x3dhServiceProvider);
    final pfsService = ref.read(pfsSessionServiceProvider);

    try {
      // 1. Pastikan prekey lokal sudah digenerate (idempotent, skip jika sudah ada)
      //    userId di sini = identitas lokal pengguna dari mock identity provider.
      final localUserId = ref.read(currentUserIdentityProvider).id;
      await x3dh.generateAndPublishPreKeys(userId: localUserId);

      // 2. Lakukan X3DH dengan peer untuk mendapat shared secret 32 bytes
      //    widget.chatId digunakan sebagai peerId (dalam app nyata: UUID peer dari server)
      final x3dhResult = await x3dh.initiateSenderX3DH(widget.chatId);

      // 3. Init PFS session menggunakan shared secret dari X3DH
      //    (peerIdentityPublicKeyBytes = identity public key peer dari X3DH)
      await pfsService.initSession(
        sessionId: widget.chatId,
        peerIdentityPublicKeyBytes: x3dhResult.senderIdentityPublicBytes,
      );
    
    // -- FAKE ROUTING TRACE SIMULATION --
    if (mounted) {
      final traceNodes = [
        '[SEC_RELAY] Bouncing traffic via node 192.168.84.22...',
        '[SEC_RELAY] Routing through onion skin layer 1...',
        '[SYS_AUTH] Verifying peer identity keys (X3DH)...',
        '[SYS_AUTH] Establishing Forward Secrecy Session (PFS)...'
      ];
      
      for (final trace in traceNodes) {
        setState(() {
          _messages.add(Message(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: widget.chatId,
            text: trace,
            senderId: 'SYSTEM',
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    // ignore: avoid_print
    print('[X3DH+PFS] Session initialized for chatId=${widget.chatId}, '
          'epoch=${pfsService.currentEpoch(widget.chatId)}');

    } catch (e) {
      // ignore: avoid_print
      print('[X3DH] Handshake failed ($e) — falling back to demo zero-key PFS.');
      // Fallback: jika X3DH gagal (belum ada prekey peer), gunakan zero key
      await pfsService.initSession(
        sessionId: widget.chatId,
        peerIdentityPublicKeyBytes: Uint8List(32),
      );
    }

    if (mounted) {
      setState(() {
        _pfsReady = true;
        _isInitializing = false;
        _pfsEpoch = pfsService.currentEpoch(widget.chatId);
      });
    }

    // ── Koneksi WebSocket ────────────────────────────────────────────────────
    final wsService = ref.read(webSocketServiceProvider);
    wsService.connect(Env.webSocketUrl);

    wsService.messageStream.listen((rawMessage) async {
      if (!mounted) return;

      // Coba parse sebagai PfsEncryptedPacket dari WebSocket
      final rawText = rawMessage.text;
      final packet = PfsEncryptedPacket.fromJson(rawText);

      if (packet != null && _pfsReady) {
        // Pesan terenkripsi PFS — decode dengan epoch yang sesuai
        try {
          final plaintext = await pfsService.decryptFromPacket(
            widget.chatId,
            packet,
          );
          if (mounted) {
            setState(() {
              _messages.add(Message(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                sessionId: widget.chatId,
                text: plaintext,
                senderId: 'SC',
                timestamp: DateTime.now(),
              ));
            });
            _scrollToBottom();
          }
        } catch (e) {
          // ignore: avoid_print
          print('[PFS] Decryption error (epoch ${packet.epoch}): $e');
        }
      } else {
        // Pesan biasa (plaintext fallback atau pesan sistem)
        if (mounted) {
          setState(() => _messages.add(rawMessage));
          _scrollToBottom();
        }
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
        HapticFeedback.heavyImpact();
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
    // Wipe semua session key PFS dari memory — jaminan forward secrecy
    ref.read(pfsSessionServiceProvider).expireSession(widget.chatId);

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
          if (_isInitializing)
            Positioned.fill(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(bottom: 80),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return Align(
                    alignment: index % 2 == 0 ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 200,
                      height: 60,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.terminalDim.withValues(alpha: 0.1),
                        border: Border.all(color: AppTheme.terminalDim.withValues(alpha: 0.3)),
                      ),
                    ),
                  );
                },
              ),
            )
          else if (_messages.isEmpty)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, color: AppTheme.terminalDim, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'END-TO-END ENCRYPTED',
                      style: AppTheme.darkTheme.textTheme.labelLarge?.copyWith(
                        color: AppTheme.terminalDim,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No prior history found on this device.',
                      style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned.fill(
              child: OptimizedMessageList(
                messages: _messages,
                scrollController: _scrollController,
                localUserId: 'ME',
              ),
            ),

          // Connection Banner Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: StreamBuilder<WsConnectionState>(
              stream: ref.watch(webSocketServiceProvider).connectionStateStream,
              initialData: ref.watch(webSocketServiceProvider).currentState,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final bool isOffline = state == WsConnectionState.disconnected || state == WsConnectionState.reconnecting;
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: isOffline ? 30 : 0,
                  color: AppTheme.warningRed,
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning, size: 14, color: AppTheme.terminalBg),
                        const SizedBox(width: 8),
                        Text(
                          state == WsConnectionState.reconnecting
                              ? 'CONNECTION LOST - RETRYING...'
                              : 'NO CONNECTION',
                          style: const TextStyle(
                            color: AppTheme.terminalBg,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            fontFamily: 'IBM Plex Mono',
                          ),
                        ),
                      ],
                    ),
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
                  // Command Menu ──────────────────────────────────────────
                  if (_showCommandMenu)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppTheme.terminalBorder)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildCommandItem(
                            icon: Icons.timer,
                            label: 'EPHEMERAL',
                            color: AppTheme.warningAmber,
                            onTap: () {
                              setState(() => _showCommandMenu = false);
                              _sendEphemeralText();
                            },
                          ),
                          _buildCommandItem(
                            icon: Icons.photo_camera_front,
                            label: 'VIEW_ONCE',
                            color: AppTheme.accentGreenBright,
                            onTap: () {
                              setState(() => _showCommandMenu = false);
                              _sendViewOnceMedia();
                            },
                          ),
                          _buildCommandItem(
                            icon: Icons.description,
                            label: 'SEC_DOC',
                            color: AppTheme.accentGreen,
                            onTap: () {
                              setState(() => _showCommandMenu = false);
                              _openDemoDocument();
                            },
                          ),
                          _buildCommandItem(
                            icon: Icons.dangerous,
                            label: 'KILL_SW',
                            color: AppTheme.warningRed,
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              setState(() => _showCommandMenu = false);
                              _simulateRemoteKillSwitch();
                            },
                          ),
                          _buildCommandItem(
                            icon: Icons.layers,
                            label: 'STEG_ENC',
                            color: Colors.purpleAccent,
                            onTap: () {
                              setState(() => _showCommandMenu = false);
                              _sendStegoPayload();
                            },
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16).copyWith(top: _showCommandMenu ? 16 : 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Toggle Command Menu Button
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _showCommandMenu = !_showCommandMenu);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _showCommandMenu ? AppTheme.accentGreen.withValues(alpha: 0.1) : Colors.transparent,
                              border: Border.all(color: _showCommandMenu ? AppTheme.accentGreen : AppTheme.terminalDim),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              _showCommandMenu ? Icons.close : Icons.add,
                              color: _showCommandMenu ? AppTheme.accentGreen : Colors.grey[400],
                            ),
                          ),
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
                                    cursorColor: AppTheme.accentGreen,
                                    cursorWidth: 8, // Block cursor effect
                                    cursorRadius: const Radius.circular(0),
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
                              border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.5)),
                              boxShadow: AppTheme.glowGreen,
                            ),
                            child: const Icon(Icons.send, color: AppTheme.accentGreen, size: 18),
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

  Widget _buildCommandItem({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'IBM Plex Mono',
                letterSpacing: 1,
              ),
            ),
          ],
        ),
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


