import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/extension_workflow_service.dart';
import '../services/mobile_api.dart';

Future<void> openVisualEditor(
  BuildContext context, {
  required MobileApi api,
  required String moduleId,
  required String kind,
  int? recordId,
  String title = 'Editor',
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: NativeVisualEditor(
        api: api,
        moduleId: moduleId,
        kind: kind,
        recordId: recordId,
      ),
    ),
  ),
);

class NativeVisualEditor extends StatefulWidget {
  final MobileApi api;
  final String moduleId, kind;
  final int? recordId;
  const NativeVisualEditor({
    super.key,
    required this.api,
    required this.moduleId,
    required this.kind,
    this.recordId,
  });
  @override
  State<NativeVisualEditor> createState() => _NativeVisualEditorState();
}

class _NativeVisualEditorState extends State<NativeVisualEditor> {
  VisualWidgetSession? _session;
  MethodChannel? _channel;
  String? _error;
  Timer? _timeout;
  Timer? _leaseRenewal;
  int _generation = 0;
  bool _ready = false, _dirty = false, _exporting = false, _leaving = false;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      _load();
    }
  }

  Future<void> _close(VisualWidgetSession session) async {
    try {
      await widget.api.request(
        '/native/visual',
        method: 'POST',
        body: {
          'module_id': widget.moduleId,
          'operation': 'close',
          'lease_token': session.lease,
        },
      );
    } catch (_) {
      /* The server also expires abandoned leases. */
    }
  }

  Future<void> _load() async {
    _timeout?.cancel();
    _leaseRenewal?.cancel();
    final generation = ++_generation;
    final previous = _session;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    setState(() {
      _session = null;
      _error = null;
      _ready = false;
    });
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted && generation == _generation && !_ready) {
        ++_generation;
        _leaseRenewal?.cancel();
        final abandoned = _session;
        setState(() {
          _session = null;
          _error = 'The editor could not finish loading. Check your connection and retry.';
        });
        if (abandoned != null) unawaited(_close(abandoned));
      }
    });
    if (previous != null) unawaited(_close(previous));
    try {
      final data = await widget.api.request(
        '/native/visual',
        method: 'POST',
        body: {
          'module_id': widget.moduleId,
          'operation': 'describe',
          'kind': widget.kind,
          if (widget.recordId != null) 'record_id': widget.recordId,
        },
      ) as Map;
      final session = VisualWidgetSession.parse(data, widget.api.origin);
      if (!mounted || generation != _generation) {
        await _close(session);
        return;
      }
      setState(() => _session = session);
      _leaseRenewal = Timer.periodic(const Duration(minutes: 8), (_) async {
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          return;
        }
        try {
          await widget.api.request(
            '/native/visual',
            method: 'POST',
            body: {
              'module_id': widget.moduleId,
              'operation': 'renew',
              'lease_token': session.lease,
            },
          );
        } catch (error) {
          if (mounted) setState(() => _error = error.toString());
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        _timeout?.cancel();
        setState(() => _error = error.toString());
      }
    }
  }

  void _created(int id) {
    final channel = MethodChannel('com.magicai.mobile/visual/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'message') return;
      final message = _session?.readMessage(call.arguments);
      if (message == null) return;
      final payload = message['payload'] as Map;
      switch (message['type']) {
        case 'ready':
          _timeout?.cancel();
          setState(() {
            _ready = true;
            _error = null;
          });
        case 'dirty':
          setState(() => _dirty = true);
        case 'saved':
          setState(() => _dirty = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Project saved')));
        case 'error':
          setState(
            () => _error =
                '${payload['message'] ?? 'The editor request failed.'}',
          );
        case 'export':
          if (_exporting) return;
          final data = payload['data'];
          if (data is! String || !data.startsWith('data:image/png;base64,')) {
            return;
          }
          _exporting = true;
          try {
            final bytes = base64Decode(
              data.substring('data:image/png;base64,'.length),
            );
            if (bytes.length > 20 * 1024 * 1024) {
              throw const ApiFailure('Export a smaller image (maximum 20 MB).');
            }
            await SecureStore.invokeMethod<void>('saveImage', {'bytes': bytes});
          } catch (error) {
            if (mounted) setState(() => _error = error.toString());
          } finally {
            _exporting = false;
          }
      }
    });
  }

  Future<void> _command(String command) async {
    try {
      await _channel?.invokeMethod<void>('command', {
        'type': command,
        'nonce': _session!.nonce,
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to reach the editor. Please reload.');
      }
    }
  }

  Future<void> _confirmLeave() async {
    if (_leaving) return;
    _leaving = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave editor?'),
        content: const Text(
          'Save your changes before leaving, or discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _leaseRenewal?.cancel();
    _channel?.setMethodCallHandler(null);
    if (_session != null) unawaited(_close(_session!));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This visual editor is available in the Android app.'),
        ),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: ColoredBox(
        color: const Color(0xFF131620),
        child: Column(
          children: [
            if (_session != null)
              ColoredBox(
                color: const Color(0xFF1E2230),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _dirty ? 'Unsaved changes' : 'Editor',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    for (final command in _session!.commands)
                      TextButton.icon(
                        onPressed: _ready ? () => _command(command) : null,
                        icon: Icon(
                          command == 'save'
                              ? Icons.save_outlined
                              : Icons.file_download_outlined,
                        ),
                        label: Text(command == 'save' ? 'Save' : 'Export'),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _dirty ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: Stack(
                children: [
                  if (_session != null)
                    AndroidView(
                      key: ValueKey(_session!.nonce),
                      viewType: 'com.magicai.mobile/visual',
                      creationParamsCodec: const StandardMessageCodec(),
                      creationParams: {
                        'url': _session!.url.toString(),
                        'entry': _session!.entry.toString(),
                        'nonce': _session!.nonce,
                      },
                      onPlatformViewCreated: _created,
                    ),
                  if (!_ready && _error == null)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0xFF131620),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
