import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/chat_session.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/terminal_avatar.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  String _selectedFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // [Phase B] Mulai background worker untuk ephemeral cleanup saat di rootscreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ephemeralCleanupServiceProvider).startSweeping();
    });
  }

  @override
  void dispose() {
    // Matikan timer saat keluar (walaupun ini root screen)
    // Dalam real implementation, bisa dikaitkan ke AppLifecycleState
    ref.read(ephemeralCleanupServiceProvider).stopSweeping();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by main app wrapper
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.terminalBg,
            border: Border(bottom: BorderSide(color: AppTheme.terminalDim)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Avatar
                      TerminalAvatar(
                        name: 'AGENT',
                        size: 40,
                        borderColor: AppTheme.accentGreen.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('> SECURE_CHATS', style: AppTheme.darkTheme.textTheme.labelLarge?.copyWith(color: AppTheme.accentGreen, letterSpacing: 2)),
                          Row(
                            children: [
                              Container(width: 6, height: 6, color: AppTheme.accentGreen.withValues(alpha: 0.5)),
                              const SizedBox(width: 4),
                              Text('Encrypted_Connection::Active', style: AppTheme.darkTheme.textTheme.labelSmall?.copyWith(color: Colors.grey[500])),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminalDim),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.edit_square, size: 18, color: AppTheme.accentGreen),
                      onPressed: () {
                        _showNewChatDialog();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.terminalDim),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('>', style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: TextField(
                      style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(color: AppTheme.accentGreen),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'EXECUTE_SEARCH...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.rectangle, size: 16, color: AppTheme.accentGreen),
                  )
                ],
              ),
            ),
          ),
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 16),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: AppTheme.terminalDim)),
              child: Row(
                children: [
                  _buildFilterTab('ALL', 'all'),
                  Container(width: 1, height: 20, color: AppTheme.terminalDim),
                  _buildFilterTab('DIRECT', 'direct'),
                  Container(width: 1, height: 20, color: AppTheme.terminalDim),
                  _buildFilterTab('GROUPS', 'groups'),
                ],
              ),
            ),
          ),
          // Chat List
          Expanded(
            child: _buildChatList(),
          )
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildChatList() {
    final chatSessionsAsync = ref.watch(chatSessionsProvider);

    return chatSessionsAsync.when(
      data: (sessions) {
        final filtered = _filterSessions(sessions);
        
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              '> NO_ACTIVE_CONNECTIONS',
              style: TextStyle(
                color: Colors.grey[600],
                fontFamily: 'IBM Plex Mono',
                letterSpacing: 1,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(bottom: 80),
          itemCount: filtered.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final session = filtered[index];
            // Simple heuristic to distinguish groups (e.g. contains :: or starts with #)
            final isGroup = session.title.contains('::') || session.title.startsWith('#');
            
            return _buildChatListItem(
              title: session.title,
              time: _formatTime(session.lastMessageAt ?? session.createdAt),
              isVerified: session.peerPublicKeyB64 != null, // Verified if we have peer key
              isConfidential: true,
              subType: isGroup ? 'TYPE:Group' : 'TYPE:Direct',
              borderColor: isGroup ? Colors.purple[400]! : AppTheme.accentGreen,
              icon: isGroup ? Icons.groups : Icons.chevron_right,
              onTap: () => context.push('/chat/${session.id}?title=${Uri.encodeComponent(session.title)}'),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accentGreen),
      ),
      error: (e, st) => Center(
        child: Text('ERR: $e', style: const TextStyle(color: AppTheme.warningRed)),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(time.year, time.month, time.day);
    
    if (msgDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}_hrs';
    }
    return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}';
  }

  List<ChatSession> _filterSessions(List<ChatSession> sessions) {
    return sessions.where((session) {
      // Filter by Search Query
      final matchesSearch = session.title.toLowerCase().contains(_searchQuery.toLowerCase());
      // Filter by Tab
      bool matchesTab = true;
      final isGroup = session.title.contains('::') || session.title.startsWith('#');
      
      if (_selectedFilter == 'direct') {
        matchesTab = !isGroup;
      } else if (_selectedFilter == 'groups') {
        matchesTab = isGroup;
      }
      return matchesSearch && matchesTab;
    }).toList();
  }

  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.terminalBg,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.terminalDim),
            borderRadius: BorderRadius.circular(4),
          ),
          title: Text(
            '> INIT_NEW_CONNECTION',
            style: const TextStyle(color: AppTheme.accentGreen, fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.bold),
          ),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: AppTheme.accentGreen, fontFamily: 'IBM Plex Mono'),
            decoration: InputDecoration(
              hintText: 'Enter Contact ID (e.g. CHMR-101)...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.terminalDim)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentGreen)),
            ),
            onSubmitted: (value) {
              context.pop(); // close dialog
              if (value.isNotEmpty) {
                context.push('/chat/$value?title=$value');
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildFilterTab(String title, String value) {
    bool isSelected = _selectedFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = value),
        child: Container(
          color: isSelected ? AppTheme.accentGreen : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          child: Text(
            '[$title]',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: isSelected ? AppTheme.terminalBg : Colors.grey[500],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatListItem({
    required String title,
    required String time,
    required Color borderColor,
    required IconData icon,
    bool isVerified = false,
    bool isConfidential = false,
    String? subStatus,
    Color? subStatusColor,
    String? subType,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.terminalCard,
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: borderColor.withValues(alpha: 0.1),
              blurRadius: 10,
            )
          ],
        ),
        child: Row(
          children: [
            // Left colored bar
            Container(width: 4, height: 40, color: borderColor),
            const SizedBox(width: 12),
            // Avatar — local TerminalAvatar, no network request
            TerminalAvatar(
              name: title,
              size: 40,
              borderColor: AppTheme.terminalDim,
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(title,
                            style: TextStyle(
                                color: borderColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(time, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontFamily: 'IBM Plex Mono')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isVerified) ...[
                        const Icon(Icons.verified_user, size: 10, color: AppTheme.accentGreen),
                        const SizedBox(width: 4),
                        Text('ID:Verified', style: TextStyle(color: Colors.grey[400], fontSize: 9)),
                        const SizedBox(width: 12),
                      ],
                      if (subType != null) ...[
                        Text(subType, style: TextStyle(color: Colors.grey[400], fontSize: 9)),
                        const SizedBox(width: 12),
                      ],
                      if (isConfidential)
                        Text('[CONFIDENTIAL]', style: TextStyle(color: AppTheme.warningRed, fontSize: 9, letterSpacing: 1)),
                      if (subStatus != null)
                        Text(subStatus, style: TextStyle(color: subStatusColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: borderColor, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 24, top: 12, left: 24, right: 24),
      decoration: const BoxDecoration(
        color: AppTheme.terminalBg,
        border: Border(top: BorderSide(color: AppTheme.terminalDim)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildNavItem(Icons.chat, 'CHATS', true, null),
          _buildNavItem(Icons.contacts, 'DIR', false, null),
          // Center Scan Button
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.terminalBg,
              border: Border.all(color: AppTheme.accentGreen),
              boxShadow: AppTheme.glowGreen,
            ),
            child: const Icon(Icons.qr_code_scanner, color: AppTheme.accentGreen, size: 24),
          ),
          _buildNavItem(Icons.folder_shared, 'VAULT', false, null),
          _buildNavItem(Icons.settings, 'CFG', false, () => context.push('/audit')),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.accentGreen.withValues(alpha: 0.1) : Colors.transparent,
              border: Border.all(color: isActive ? AppTheme.accentGreen : Colors.transparent),
              boxShadow: isActive ? AppTheme.glowGreen : null,
            ),
            child: Icon(icon, color: isActive ? AppTheme.accentGreen : Colors.grey[600], size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2, color: isActive ? AppTheme.accentGreen : Colors.grey[600])),
        ],
      ),
    );
  }
}
