import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/audit_log.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/ascii_spinner.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  List<AuditLog> _logs = [];
  bool _isLoading = true;
  bool? _isChainValid;
  String _statusMessage = 'AWAITING_VERIFICATION...';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    
    // We cannot access _auditDb directly from providers without exposing it,
    // but we can query it via a raw approach here just to display them. 
    // Ideally we'd add an `getAllLogsDescending` to AuditLogService, but let's do this directly.
    try {
      final databasesPath = await getDatabasesPath();
      final path = p.join(databasesPath, 'chimera_audit.db');
      
      final storage = ref.read(secureStorageProvider);
      final key = await storage.read(key: 'chimera_audit_db_key');
      
      if (key == null) {
        setState(() {
          _logs = [];
          _isLoading = false;
        });
        return;
      }

      final db = await openDatabase(path, password: key);
      final maps = await db.query('audit_logs', orderBy: 'timestamp DESC', limit: 100);
      await db.close();

      setState(() {
        _logs = maps.map((m) => AuditLog.fromMap(m)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[AuditLogScreen] Failed to load logs: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyIntegrity() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'CALCULATING_SHA256_HASHES...';
    });

    // Simulate some calculation time for effect
    await Future.delayed(const Duration(seconds: 1));

    final service = ref.read(auditLogServiceProvider);
    final isValid = await service.verifyChain();

    setState(() {
      _isChainValid = isValid;
      _isLoading = false;
      _statusMessage = isValid 
        ? 'INTEGRITY_VERIFIED_100%' 
        : 'CRITICAL_ALERT: CHAIN_BROKEN/TAMPERED_DATA';
    });
  }

  Future<void> _simulateTampering() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'POISONING_DATABASE...';
    });

    try {
      final databasesPath = await getDatabasesPath();
      final path = p.join(databasesPath, 'chimera_audit.db');
      final storage = ref.read(secureStorageProvider);
      final key = await storage.read(key: 'chimera_audit_db_key');
      
      if (key != null) {
        final db = await openDatabase(path, password: key);
        // deliberately update the latest log to break the hash
        final maps = await db.query('audit_logs', orderBy: 'timestamp DESC', limit: 1);
        if (maps.isNotEmpty) {
           await db.update('audit_logs', {'details': 'TAMPERED DATA'}, where: 'id = ?', whereArgs: [maps.first['id']]);
        }
        await db.close();
      }
    } catch (e) {
      debugPrint('[AuditLogScreen] Tamper failed: $e');
    }

    await Future.delayed(const Duration(milliseconds: 500));
    await _loadLogs();

    setState(() {
       _statusMessage = 'DATA_TAMPERED._RUN_VERIFICATION_TO_DETECT.';
       _isChainValid = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isChainValid == null 
        ? Colors.grey[500] 
        : (_isChainValid! ? AppTheme.accentGreen : AppTheme.warningRed);

    return Scaffold(
      backgroundColor: Colors.transparent, // Uses PixelGrid Background
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
                children: [
                   Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 20, color: AppTheme.accentGreen),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('system_audit_log', style: TextStyle(color: AppTheme.accentGreen, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const Spacer(),
                  const Icon(Icons.admin_panel_settings, size: 20, color: AppTheme.accentGreen),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Control Panel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.terminalDim)),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.terminalCard,
                    border: Border.all(color: statusColor!),
                    boxShadow: _isChainValid == true ? AppTheme.glowGreen : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isChainValid == null ? Icons.pending_actions : (_isChainValid! ? Icons.verified : Icons.warning_amber),
                        color: statusColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.security, size: 16),
                        label: const Text('VERIFY INTEGRITY'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentGreen,
                          side: const BorderSide(color: AppTheme.accentGreen),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 10),
                        ),
                        onPressed: _isLoading ? null : _verifyIntegrity,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bug_report, size: 16),
                        label: const Text('MOCK TAMPER'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.warningRed,
                          side: const BorderSide(color: AppTheme.warningRed),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 10),
                        ),
                        onPressed: _isLoading ? null : _simulateTampering,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          
          // Log List
          Expanded(
            child: _isLoading 
                ? const Center(child: AsciiSpinner(color: AppTheme.accentGreen))
                : _logs.isEmpty 
                  ? const Center(child: Text("NO LOGS FOUND", style: TextStyle(color: AppTheme.terminalDim, letterSpacing: 2)))
                  : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final isGenesis = log.previousHash == 'GENESIS';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.terminalDim),
                    color: AppTheme.terminalCard,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ID: ${log.id}', style: const TextStyle(color: AppTheme.terminalDim, fontSize: 9)),
                          Text(log.timestamp.toIso8601String().split('T').join(' ').split('.').first, style: const TextStyle(color: AppTheme.terminalDim, fontSize: 9)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(log.action, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text(log.details, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                      const SizedBox(height: 8),
                      const Divider(color: AppTheme.terminalDim, height: 1),
                      const SizedBox(height: 8),
                      // Hashes
                      Text('Prev Hash: ${isGenesis ? log.previousHash : '${log.previousHash.substring(0, 16)}...'}', style: TextStyle(color: Colors.grey[600], fontSize: 8, fontFamily: 'IBM Plex Mono')),
                      const SizedBox(height: 2),
                      Text('Curr Hash: ${log.currentHash.substring(0, 16)}...', style: const TextStyle(color: AppTheme.accentGreen, fontSize: 8, fontFamily: 'IBM Plex Mono')),
                    ],
                  ),
                );
              },
            )
          )
        ],
      )
    );
  }
}
