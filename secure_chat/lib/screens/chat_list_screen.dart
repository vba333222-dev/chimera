import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String _selectedFilter = 'all';

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
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: AppTheme.accentGreen.withOpacity(0.5)),
                          image: const DecorationImage(
                            image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuDBRwVSor3oJs9mzbyK6RUpvQliakEDEBp8zapfukz-jfoaOiPvJ0l1053Dw1IR9jgoEoD69gaLL0HJsxUJaDW3LVJshh0IDqE1UerUAv3OSv4bXYdKm6SRCI9RD4lexdE3LW-p6w2m0zY4ZvYApA6YL1XFIuJ4sSRQsMA5Fb27QTnBRdQJs1jzbSNJer2lhyXGzjD3aaiRH422Xs_iW6jv-fuIEGNukkvlHndaqKyYA7yQn1M2gYFhZkpfTSXz7TyfGpwH7oStUHdm'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('> SECURE_CHATS', style: AppTheme.darkTheme.textTheme.labelLarge?.copyWith(color: AppTheme.accentGreen, letterSpacing: 2)),
                          Row(
                            children: [
                              Container(width: 6, height: 6, color: AppTheme.accentGreen.withOpacity(0.5)),
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
                      onPressed: () {},
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
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildChatListItem(
                  title: 'Alpha_Team_Net',
                  time: '1042_hrs',
                  imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDyLuIo7hLkH0zX_fm3mVIQ-GrkLb1Czf-EHWvJeDdzMfJAldqHMojpb_3vnLX2xTY1-qhwLt4d25DkvHJG4E0CcNtKgReqT1LoDqcBhFGpxEEB2bdreu-XVkFrCTeYs00Mj1AXDZiEV6jTCjsSO7X-_Pupl3Br98vaW68yjxDCtnT_913e2UZLts6nK83y2HTuZAgx9aP8f3gdpzzhGKmzjAE_YfFRJlxlTXrzO-hkVNMhASEXgcIX05y0wGebfU-fAcCmV1AZapk6',
                  isVerified: true,
                  isConfidential: true,
                  borderColor: AppTheme.accentGreen,
                  icon: Icons.terminal,
                  onTap: () => context.push('/chat/alpha?title=Alpha_Team_Net'),
                ),
                const SizedBox(height: 12),
                _buildChatListItem(
                  title: 'HR_Unit :: S.Jenkins',
                  time: '0915_hrs',
                  imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCxtKnLAYGlZRLfIuRP23X81cx7DILcOLpSd0Ui1oIYn-wId8Xrtbze8zDxda7BRhSaUZK03TtGffMrXJID8OKi7b4RXhUH9r86ljp56S3o4mybOlp_Zro9O0D-7x0aKT4JnwDLWukuvbExW4NsW1OavOznTj5Z5hUO8FZEoRTUtVHNdubX7JMd6OQ8EfnwKNFBweQF-jZsgyeYggttB_VTzHqGmiyz4e3NnrnL1RcAlnWNPRKJgcmBU0RA4jaI_z846NVanOFCM0X-',
                  isVerified: false,
                  subStatus: 'Restricted',
                  subStatusColor: AppTheme.warningRed,
                  subType: 'TYPE:Internal',
                  borderColor: AppTheme.warningRed,
                  icon: Icons.do_not_disturb_on,
                  onTap: () => context.push('/chat/hr?title=HR_Unit'),
                ),
                const SizedBox(height: 12),
                _buildChatListItem(
                  title: 'Board_Strategy_Rm',
                  time: 'T-minus_24h',
                  imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCpoOYRg30pX7SZ1ftgeRgeTWVD4VPrsG2lE5nHwcQVpZ6hPWtFi6ELX2s2jAMJI0lVEHuhthYaAG3i0hQbT9BIqaTteI99FG7CYZ45MIP7GCGcC897OxYKchS39wQYcUNB06WX_xfNeZP5l-4yb9QeAveRCTiprE1Boy0s-wtZKNNz_172DH5UTd9SoOEG8dJKNSwHGOHxcCdqSWvquFx6Natb3aXmyMHo1yXHaTaf1EiNOr45wKIg8z0cZ5Uf4_ibolL8PqFVBOet',
                  subStatus: 'LVL:Top_Secret',
                  subStatusColor: Colors.purple[400],
                  subType: 'Enc:E2EE',
                  borderColor: AppTheme.warningRed,
                  icon: Icons.vpn_key,
                  onTap: () => context.push('/chat/board?title=Board_Strategy_Rm'),
                ),
                const SizedBox(height: 12),
                _buildChatListItem(
                  title: 'Legal_Dept_Main',
                  time: 'Mon',
                  imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBo6l5KsMiM59f2kgUiFj_qw1b-sppucd_VwFO80AoHkqSuoB-qbza-ig0xbmasNZ7K0xBvWS0-lwOEGwYVW-E2pM54JnBlzDQS5D5tfrLo9QoKmxFgtPGRjOwL7SLK3keKhxuW8C9dGixYShHWA_em2y3UJHjDhrt6gLB5BaUv4Cq-78YmwqLocomXXG-vasjwb6Hj7xYX8bZgS3CJ97omr1jSvPLcnTAHjoUsSkebC22RvniK72rhfpd5h1mImSg9GRc9HY4dt4CI',
                  isVerified: true,
                  borderColor: AppTheme.accentGreen,
                  icon: Icons.chevron_right,
                  onTap: () => context.push('/chat/legal?title=Legal_Dept_Main'),
                ),
                const SizedBox(height: 80), // Padding for bottom nav
              ],
            ),
          )
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
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
    required String imageUrl,
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
              color: borderColor.withOpacity(0.1),
              blurRadius: 10,
            )
          ],
        ),
        child: Row(
          children: [
            // Left colored bar
            Container(width: 4, height: 40, color: borderColor),
            const SizedBox(width: 12),
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.terminalDim),
                image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
              ),
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
          _buildNavItem(Icons.chat, 'CHATS', true),
          _buildNavItem(Icons.contacts, 'DIR', false),
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
          _buildNavItem(Icons.folder_shared, 'VAULT', false),
          _buildNavItem(Icons.settings, 'CFG', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accentGreen.withOpacity(0.1) : Colors.transparent,
            border: Border.all(color: isActive ? AppTheme.accentGreen : Colors.transparent),
            boxShadow: isActive ? AppTheme.glowGreen : null,
          ),
          child: Icon(icon, color: isActive ? AppTheme.accentGreen : Colors.grey[600], size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2, color: isActive ? AppTheme.accentGreen : Colors.grey[600])),
      ],
    );
  }
}
