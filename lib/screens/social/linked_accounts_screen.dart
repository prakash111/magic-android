import 'package:flutter/material.dart';

import '../../models/social_account.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class LinkedAccountsScreen extends StatefulWidget {
  const LinkedAccountsScreen({super.key});

  @override
  State<LinkedAccountsScreen> createState() => _LinkedAccountsScreenState();
}

class _LinkedAccountsScreenState extends State<LinkedAccountsScreen> {
  List<SocialAccount> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    final accounts = await ApiService.getSocialPlatforms();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleConnection(SocialAccount account) async {
    final willConnect = !account.isConnected;

    if (!willConnect) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Disconnect ${account.displayName}?'),
          content: Text(
            'Scheduled posts targeting ${account.displayName} will not be published automatically until you reconnect.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await ApiService.disconnectSocialPlatform(account.id);
      await _loadAccounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from ${account.displayName}.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    // Connect Flow: Prompt for handle/username
    final handleController = TextEditingController(
      text: account.handle.isNotEmpty ? account.handle : '@',
    );

    final enteredHandle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Connect ${account.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your ${account.displayName} username or profile handle to register with your MagicAI account.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: handleController,
              decoration: const InputDecoration(
                labelText: 'Profile Handle',
                hintText: '@username',
                prefixIcon: Icon(Icons.alternate_email, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, handleController.text.trim()),
            child: const Text('Connect Account'),
          ),
        ],
      ),
    );

    if (enteredHandle == null ||
        enteredHandle.isEmpty ||
        enteredHandle == '@') {
      return;
    }

    setState(() => _isLoading = true);
    await ApiService.connectSocialPlatform(
      account.platform,
      handle: enteredHandle,
    );
    await _loadAccounts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${account.displayName}!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'x':
      case 'twitter':
        return const Color(0xFF38BDF8);
      case 'instagram':
        return const Color(0xFFE1306C);
      case 'linkedin':
        return const Color(0xFF0A66C2);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'tiktok':
        return const Color(0xFFFE2C55);
      case 'youtube':
      case 'youtube-shorts':
        return const Color(0xFFFF0000);
      default:
        return AppTheme.primary;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'x':
      case 'twitter':
        return Icons.alternate_email;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'linkedin':
        return Icons.business_outlined;
      case 'facebook':
        return Icons.facebook;
      case 'tiktok':
        return Icons.music_note;
      case 'youtube':
      case 'youtube-shorts':
        return Icons.play_arrow;
      default:
        return Icons.share;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectedCount = _accounts.where((a) => a.isConnected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Social Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync metrics',
            onPressed: _loadAccounts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAccounts,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overview Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF312E81), Color(0xFF4C1D95)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.link,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$connectedCount of ${_accounts.length} Platforms Connected',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Direct API publishing linked with your MagicAI account.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Available Channels',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // Accounts List
                  ..._accounts.map((account) {
                    final color = _getPlatformColor(account.platform);
                    final icon = _getPlatformIcon(account.platform);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: color, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        account.displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (account.isConnected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.success.withOpacity(
                                              0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 3,
                                                backgroundColor:
                                                    AppTheme.success,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Connected',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.success,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    account.isConnected &&
                                            account.handle.isNotEmpty
                                        ? account.handle
                                        : 'Not connected',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  if (account.isConnected &&
                                      account.followers > 0) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      '${account.followers.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} followers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: account.isConnected
                                    ? AppTheme.error
                                    : AppTheme.primary,
                                side: BorderSide(
                                  color: account.isConnected
                                      ? AppTheme.error.withOpacity(0.5)
                                      : AppTheme.primary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => _toggleConnection(account),
                              child: Text(
                                account.isConnected ? 'Disconnect' : 'Connect',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
