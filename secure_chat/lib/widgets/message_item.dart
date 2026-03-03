// lib/widgets/message_item.dart
//
// Widget untuk satu item pesan dalam daftar chat.
//
// Menggunakan AutomaticKeepAliveClientMixin untuk mencegah rebuild
// saat item di-scroll keluar viewport dan kembali masuk.

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'burn_on_read_media.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MessageItem
// ─────────────────────────────────────────────────────────────────────────────

class MessageItem extends StatefulWidget {
  final Message message;
  final bool isSelf;
  final bool animateTypewriter;

  const MessageItem({
    super.key,
    required this.message,
    required this.isSelf,
    this.animateTypewriter = false,
  });

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem>
    with AutomaticKeepAliveClientMixin {

  // ── AutomaticKeepAliveClientMixin ──────────────────────────────────────────
  // Mengembalikan true berarti Flutter akan mempertahankan state widget ini
  // di memory meskipun item scrolled off screen.
  //
  // Efek: Saat user scroll ke atas lalu kembali ke bawah, pesan yang sudah
  // dirender TIDAK perlu rebuild ulang. Sangat signifikan untuk 1000+ pesan.
  //
  // Trade-off: Menggunakan lebih banyak RAM. Gunakan false jika memory terbatas.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // WAJIB dipanggil saat menggunakan AutomaticKeepAliveClientMixin
    super.build(context);

    final initials = widget.isSelf
        ? ''
        : (widget.message.senderId.length >= 2
            ? widget.message.senderId.substring(0, 2)
            : '??');
    final name = widget.isSelf ? 'ME' : 'Sarah_Chen';
    final timeStr =
        '${widget.message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${widget.message.timestamp.minute.toString().padLeft(2, '0')}';

    return Row(
      mainAxisAlignment:
          widget.isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!widget.isSelf) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              border: Border.all(color: Colors.grey.shade600),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'IBM Plex Mono',
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: widget.isSelf
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // ── Nama & waktu ─────────────────────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.isSelf) ...[
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontFamily: 'IBM Plex Mono',
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.lock, size: 12, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontFamily: 'IBM Plex Mono',
                      ),
                    ),
                  ],

                  // ── TTL Indicator ──────────────────────────────────────────
                  if (widget.message.expiresAt != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.hourglass_bottom,
                      size: 12,
                      color: AppTheme.warningRed,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'TTL',
                      style: const TextStyle(
                        color: AppTheme.warningRed,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'IBM Plex Mono',
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),

              // ── Bubble pesan atau Media ──────────────────────────────────
              if (widget.message.text.startsWith('SECURE_PAYLOAD:'))
                // Render Media (Burn On Read)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  child: BurnOnReadMedia(
                    filePath: widget.message.text.split('FILE://')[1].trim(),
                    participantId: widget.message.senderId,
                    onBurnt: () {
                      // Callback bisa digunakan untuk update UI segera,
                      // tapi DB di-handle oleh _handleReleaseOrCancel atau cleanup worker
                    },
                  ),
                )
              else
                // Render Teks Biasa
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.terminalCard,
                    border: Border.all(
                      color: widget.isSelf
                          ? AppTheme.accentGreen.withValues(alpha: 0.5)
                          : AppTheme.terminalBorder,
                    ),
                  ),
                  child: widget.animateTypewriter
                      ? _TypewriterText(
                          // Key memastikan state typewriter tidak di-share antar pesan
                          key: ValueKey('tw_${widget.message.id}'),
                          text: widget.message.text,
                          isSelf: widget.isSelf,
                        )
                      : _StaticText(
                          text: widget.message.text,
                          isSelf: widget.isSelf,
                        ),
                ),

              // ── Read receipt / Status ────────────────────────────────────
              if (widget.isSelf) ...[
                const SizedBox(height: 4),
                _buildStatusIcon(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon() {
    switch (widget.message.status) {
      case MessageStatus.pending:
        return Icon(
          Icons.access_time_filled, // Jam pasir/jam
          color: Colors.grey.withValues(alpha: 0.5),
          size: 14,
        );
      case MessageStatus.sent:
        return const Icon(
          Icons.check,
          color: AppTheme.accentGreen,
          size: 14,
        );
      case MessageStatus.failed:
        return const Icon(
          Icons.error_outline,
          color: AppTheme.warningRed,
          size: 14,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StaticText — CONST-friendly, tidak pernah rebuild
// ─────────────────────────────────────────────────────────────────────────────

class _StaticText extends StatelessWidget {
  final String text;
  final bool isSelf;

  const _StaticText({required this.text, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: isSelf ? AppTheme.accentGreenBright : Colors.grey.shade200,
        fontSize: 14,
        fontFamily: 'IBM Plex Mono',
        height: 1.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TypewriterText — animasi ketik untuk pesan masuk yang baru
// ─────────────────────────────────────────────────────────────────────────────

class _TypewriterText extends StatefulWidget {
  final String text;
  final bool isSelf;

  const _TypewriterText({
    super.key,
    required this.text,
    required this.isSelf,
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayed = '';
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (_index < widget.text.length) {
        setState(() {
          _displayed += widget.text[_index];
          _index++;
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
      _displayed + (_index < widget.text.length ? '█' : ''),
      style: TextStyle(
        color: widget.isSelf
            ? AppTheme.accentGreenBright
            : Colors.grey.shade200,
        fontSize: 14,
        fontFamily: 'IBM Plex Mono',
        height: 1.5,
      ),
    );
  }
}
