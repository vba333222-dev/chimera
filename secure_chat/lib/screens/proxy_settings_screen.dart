// lib/screens/proxy_settings_screen.dart
//
// Layar konfigurasi proxy dan monitoring status koneksi WebSocket.
// Mendukung: Direct / SOCKS5 / HTTP proxy dengan optional auth.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class ProxySettingsScreen extends ConsumerStatefulWidget {
  const ProxySettingsScreen({super.key});

  @override
  ConsumerState<ProxySettingsScreen> createState() => _ProxySettingsScreenState();
}

class _ProxySettingsScreenState extends ConsumerState<ProxySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  ProxyType _selectedType = ProxyType.none;
  bool _showPassword = false;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    // Load current config into form fields
    final config = ref.read(proxyConfigProvider);
    _selectedType = config.type;
    _hostController.text = config.host;
    _portController.text = config.port > 0 ? config.port.toString() : '';
    _usernameController.text = config.username ?? '';
    _passwordController.text = config.password ?? '';
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final config = ProxyConfig(
      type: _selectedType,
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password: _passwordController.text.isEmpty
          ? null
          : _passwordController.text,
    );

    await ref.read(proxyConfigProvider.notifier).save(config);

    // Update live WebSocket connection with new proxy
    await ref.read(webSocketServiceProvider).updateProxy(config);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            config.isEnabled
                ? '> PROXY SAVED: ${config.type.name.toUpperCase()} ${config.host}:${config.port}'
                : '> DIRECT CONNECTION SAVED',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          backgroundColor: AppTheme.accentGreen,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    if (_selectedType == ProxyType.none) {
      setState(() => _testResult = '> DIRECT mode — no proxy to test');
      return;
    }
    if (_hostController.text.trim().isEmpty) {
      setState(() => _testResult = '> ERROR: Host is required');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = '> Testing connection...';
    });

    final config = ProxyConfig(
      type: _selectedType,
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 1080,
      username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
      password: _passwordController.text.isEmpty ? null : _passwordController.text,
    );

    final proxyService = ref.read(networkProxyServiceProvider);

    try {
      final socket = await proxyService.buildSocket(
        targetHost: 'echo.websocket.events',
        targetPort: 443,
        config: config,
      );
      await socket.close();
      setState(() {
        _testResult =
            '> OK: Tunnel to echo.websocket.events:443 established via '
            '${config.type.name.toUpperCase()} ${config.host}:${config.port}';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _testResult = '> FAILED: ${e.toString().replaceAll('\n', ' ')}';
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wsState = ref.watch(
      webSocketServiceProvider.select((s) => s.currentState),
    );

    return Scaffold(
      backgroundColor: AppTheme.terminalBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.accentGreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'NETWORK CONFIG',
          style: TextStyle(
            color: AppTheme.accentGreen,
            fontFamily: 'monospace',
            fontSize: 14,
            letterSpacing: 4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _ConnectionBadge(state: wsState),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Section header ──────────────────────────────────────────────
            _SectionLabel('PROXY TYPE'),
            const SizedBox(height: 8),

            // ── Proxy type selector ────────────────────────────────────────
            _ProxyTypeSelector(
              selected: _selectedType,
              onChanged: (type) => setState(() {
                _selectedType = type;
                _testResult = null;
              }),
            ),

            if (_selectedType != ProxyType.none) ...[
              const SizedBox(height: 20),
              _SectionLabel('PROXY SERVER'),
              const SizedBox(height: 8),

              // ── Host ────────────────────────────────────────────────────
              _TerminalField(
                controller: _hostController,
                label: 'HOST / IP',
                hint: _selectedType == ProxyType.socks5
                    ? 'e.g. 127.0.0.1  (Tor: socks5h://127.0.0.1)'
                    : 'e.g. proxy.example.com',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Host required' : null,
              ),
              const SizedBox(height: 12),

              // ── Port ────────────────────────────────────────────────────
              _TerminalField(
                controller: _portController,
                label: 'PORT',
                hint: _selectedType == ProxyType.socks5 ? '9050 (Tor) / 1080' : '8080',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Port required';
                  final port = int.tryParse(v);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Invalid port (1–65535)';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),
              _SectionLabel('AUTHENTICATION (OPTIONAL)'),
              const SizedBox(height: 8),

              // ── Username ────────────────────────────────────────────────
              _TerminalField(
                controller: _usernameController,
                label: 'USERNAME',
                hint: 'Leave blank if no auth required',
              ),
              const SizedBox(height: 12),

              // ── Password ────────────────────────────────────────────────
              _TerminalField(
                controller: _passwordController,
                label: 'PASSWORD',
                hint: 'Leave blank if no auth required',
                obscureText: !_showPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.accentGreen.withAlpha(128),
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),

              const SizedBox(height: 20),

              // ── Test button ──────────────────────────────────────────────
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentGreen,
                  side: BorderSide(color: AppTheme.accentGreen.withAlpha(80)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.accentGreen,
                        ),
                      )
                    : const Icon(Icons.wifi_find, size: 16),
                label: Text(
                  _isTesting ? 'TESTING...' : 'TEST CONNECTION',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),

              // ── Test result ──────────────────────────────────────────────
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: _testResult!.contains('OK')
                          ? AppTheme.accentGreen
                          : AppTheme.warningAmber,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _testResult!.contains('OK')
                          ? AppTheme.accentGreen
                          : AppTheme.warningAmber,
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 32),

            // ── Save button ────────────────────────────────────────────────
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: _save,
              child: const Text(
                'SAVE & APPLY',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Clear button ───────────────────────────────────────────────
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(proxyConfigProvider.notifier).clear();
                setState(() {
                  _selectedType = ProxyType.none;
                  _hostController.clear();
                  _portController.clear();
                  _usernameController.clear();
                  _passwordController.clear();
                  _testResult = null;
                });
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('> PROXY CONFIG CLEARED',
                          style: TextStyle(fontFamily: 'monospace')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text(
                'CLEAR PROXY CONFIG',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),

            const SizedBox(height: 40),

            // ── Heartbeat info ─────────────────────────────────────────────
            _SectionLabel('CONNECTION INFO'),
            const SizedBox(height: 8),
            _ConnectionInfo(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.accentGreen.withAlpha(160),
        fontFamily: 'monospace',
        fontSize: 10,
        letterSpacing: 3,
      ),
    );
  }
}

class _ProxyTypeSelector extends StatelessWidget {
  final ProxyType selected;
  final ValueChanged<ProxyType> onChanged;

  const _ProxyTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ProxyType.values.map((type) {
        final isSelected = type == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accentGreen.withAlpha(30)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.accentGreen
                      : AppTheme.accentGreen.withAlpha(40),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    type == ProxyType.none
                        ? Icons.cable
                        : type == ProxyType.socks5
                            ? Icons.security
                            : Icons.http,
                    color: isSelected
                        ? AppTheme.accentGreen
                        : AppTheme.accentGreen.withAlpha(100),
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.name.toUpperCase(),
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.accentGreen
                          : AppTheme.accentGreen.withAlpha(100),
                      fontFamily: 'monospace',
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TerminalField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final bool obscureText;
  final Widget? suffixIcon;

  const _TerminalField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      obscureText: obscureText,
      style: TextStyle(
        color: AppTheme.accentGreen,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: AppTheme.accentGreen.withAlpha(160),
          fontFamily: 'monospace',
          fontSize: 11,
          letterSpacing: 1,
        ),
        hintStyle: TextStyle(
          color: AppTheme.accentGreen.withAlpha(60),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.accentGreen.withAlpha(60)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.accentGreen),
        ),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent, width: 2),
        ),
        errorStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: Colors.redAccent,
        ),
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  final WsConnectionState state;
  const _ConnectionBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      WsConnectionState.connected => (AppTheme.accentGreen, 'LIVE'),
      WsConnectionState.connecting => (AppTheme.warningAmber, 'CONN…'),
      WsConnectionState.reconnecting => (Colors.orangeAccent, 'RETRY'),
      WsConnectionState.disconnected => (Colors.redAccent, 'OFF'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _ConnectionInfo extends ConsumerWidget {
  const _ConnectionInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyConfig = ref.watch(proxyConfigProvider);

    final rows = [
      ('HEARTBEAT', '20s ping / 10s watchdog'),
      ('BACKOFF', '1s → 2s → 4s → 8s → 16s → 30s + jitter'),
      ('MAX HISTORY EPOCHS', '$kMaxHistoryEpochs epochs (${kMaxHistoryEpochs * 5} min)'),
      ('PROXY MODE', proxyConfig.isEnabled
          ? '${proxyConfig.type.name.toUpperCase()} ${proxyConfig.host}:${proxyConfig.port}'
          : 'DIRECT'),
      ('PROXY AUTH', proxyConfig.hasAuth ? 'YES (credentials set)' : 'NO'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: AppTheme.accentGreen.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    '${row.$1}:',
                    style: TextStyle(
                      color: AppTheme.accentGreen.withAlpha(120),
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      color: AppTheme.accentGreen,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
