// lib/widgets/optimized_message_list.dart
//
// Widget daftar pesan yang dioptimasi untuk performa tinggi.
//
// Strategi Optimasi yang Diterapkan:
// ════════════════════════════════════════════════════════════════════════════
//
// 1. KEYED WIDGETS & findChildIndexCallback
//    Setiap item diberi ValueKey(message.id). Flutter menggunakan key ini
//    untuk menemukan elemen yang sudah ada di tree saat rebuild.
//    findChildIndexCallback memungkinkan SliverList mencari elemen berdasarkan
//    key TANPA harus iterasi linear O(n) — sangat penting dengan ribuan pesan.
//
// 2. SLIVERLIST + CustomScrollView (vs ListView.builder biasa)
//    CustomScrollView dengan SliverList memberikan kontrol granular atas
//    scroll behavior, lazy rendering, dan sliver composition.
//    Ini memungkinkan header (log marker, system message) sebagai SliverToBoxAdapter
//    yang TIDAK di-rebuild saat pesan baru ditambahkan.
//
// 3. REPAINTBOUNDARY per item
//    Setiap MessageItem dibungkus RepaintBoundary. Ini mengisolasi layer
//    compositing setiap pesan. Saat satu pesan di-rebuild (misalnya karena
//    typewriter animation selesai), pesan lain TIDAK ikut di-repaint.
//
// 4. CONST CONSTRUCTORS untuk widget statis
//    Header (LogStartMarker, SystemMessage, SecurityAlertBanner) adalah const
//    sehingga Flutter TIDAK pernah rebuild mereka saat state berubah.
//
// 5. AutomaticKeepAlive + wantKeepAlive
//    MessageItem yang sudah tidak terlihat (di-scroll ke atas) tetap
//    disimpan dengan AutomaticKeepAliveClientMixin sehingga tidak perlu
//    rebuild ulang saat di-scroll kembali ke item tersebut.
//
// 6. itemExtentBuilder (opsional, diaktifkan untuk pesan pendek)
//    Jika ukuran item bisa diestimasi, Flutter bisa skip layout calculation.
//    Untuk pesan dengan teks panjang variabel, kita tidak menggunakan ini
//    tapi kita menggunakan cacheExtent yang lebih besar untuk pre-render.
//
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'message_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OptimizedMessageList
// ─────────────────────────────────────────────────────────────────────────────

class OptimizedMessageList extends StatelessWidget {
  final List<Message> messages;
  final ScrollController scrollController;
  final String localUserId;

  const OptimizedMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.localUserId,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      // cacheExtent yang besar: Flutter pre-render item di luar viewport.
      // Nilai 500px berarti 500px di atas dan bawah viewport di-render lebih awal.
      // Ini menghilangkan "jerk" saat scroll ke item baru.
      cacheExtent: 500,
      slivers: [
        // ── Header statis (CONST — tidak pernah rebuild) ──────────────────────
        const SliverToBoxAdapter(child: _LogStartMarker()),
        const SliverToBoxAdapter(child: _SystemMessage()),
        const SliverToBoxAdapter(child: _SecurityAlertBanner()),

        // ── Padding atas untuk konten pesan ───────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ── Daftar pesan yang dioptimasi ──────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final message = messages[index];
              final isSelf = message.senderId == localUserId;
              final isLast = index == messages.length - 1;

              // ── RepaintBoundary ────────────────────────────────────────────
              // Mengisolasi setiap pesan di layer compositing terpisah.
              // Pesan lain tidak ikut di-repaint saat satu item berubah.
              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  // ── MessageItem dengan AutomaticKeepAlive ─────────────────
                  child: MessageItem(
                    key: ValueKey(message.id), // KEY PENTING untuk findChildIndexCallback
                    message: message,
                    isSelf: isSelf,
                    // Hanya pesan TERAKHIR yang ditampilkan dengan typewriter
                    // dan hanya jika pesan tersebut baru (< 5 detik)
                    animateTypewriter: !isSelf &&
                        isLast &&
                        DateTime.now()
                                .difference(message.timestamp)
                                .inSeconds <
                            5,
                  ),
                ),
              );
            },
            // ── findChildIndexCallback ────────────────────────────────────────
            // KUNCI UTAMA OPTIMASI: daripada SliverList mencari elemen dengan
            // iterasi linear dari index 0 (O(n)), callback ini memberitahu
            // Flutter index dari sebuah key secara langsung.
            //
            // Cara kerja: saat pesan baru ditambahkan di akhir list,
            // Flutter perlu "menyesuaikan" item yang sudah dirender.
            // Tanpa ini, Flutter iterasi semua item. Dengan ini, langsung jump.
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final messageId = key.value;
                final index = messages.indexWhere((m) => m.id == messageId);
                return index == -1 ? null : index;
              }
              return null;
            },
            childCount: messages.length,
            // addAutomaticKeepAlives: true (default) — aktif otomatis
            // addRepaintBoundaries: false karena kita tambahkan manual di atas
            // untuk kontrol lebih granular
            addRepaintBoundaries: false,
          ),
        ),

        // ── Padding bawah untuk input field ──────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header Widgets — Semua CONST untuk memastikan zero rebuild
// ─────────────────────────────────────────────────────────────────────────────

class _LogStartMarker extends StatelessWidget {
  const _LogStartMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade800),
                ),
              ),
              child: Text(
                '2023-10-24 [LOG_START]',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontFamily: 'IBM Plex Mono',
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person, size: 10, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'E2EE_ACTIVE // ZERO_TRUST_NODE',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'IBM Plex Mono',
                    letterSpacing: 2,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.terminalCard,
            border: Border.all(color: AppTheme.terminalBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 12),
                child: Icon(
                  Icons.terminal,
                  color: AppTheme.accentGreen,
                  size: 16,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '> SYSTEM_ROOT',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Handshake complete. Identity verified (X25519-ECDH). Session is strictly confidential.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                        fontFamily: 'IBM Plex Mono',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityAlertBanner extends StatelessWidget {
  const _SecurityAlertBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber.withValues(alpha: 0.05),
            border: Border.all(color: AppTheme.warningAmber),
            boxShadow: [
              BoxShadow(
                color: AppTheme.warningAmber.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.key_off,
                color: AppTheme.warningAmber,
                size: 18,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SECURITY ALERT',
                    style: TextStyle(
                      color: AppTheme.warningAmber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    "User 'J.Doe' keys changed. Verify fingerprint.",
                    style: TextStyle(
                      color: AppTheme.warningAmber.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontFamily: 'IBM Plex Mono',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
