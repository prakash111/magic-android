import 'package:flutter/material.dart';

import '../services/app_localizations.dart';

/// Recovers a tool subtree after both synchronous and descendant build errors.
class ToolRenderBoundary extends StatefulWidget {
  const ToolRenderBoundary({
    super.key,
    required this.builder,
    required this.onRetry,
    required this.message,
  });

  final WidgetBuilder builder;
  final Future<void> Function() onRetry;
  final String message;

  /// Install once at the app root, preserving the host's handler elsewhere.
  static ErrorWidgetBuilder errorBuilder(ErrorWidgetBuilder fallback) =>
      (details) => _RenderFailureSlot(details: details, fallback: fallback);

  @override
  State<ToolRenderBoundary> createState() => _ToolRenderBoundaryState();
}

class _ToolRenderBoundaryState extends State<ToolRenderBoundary> {
  bool _failed = false;
  bool _failurePending = false;
  bool _retrying = false;
  int _revision = 0;

  void captureFailure() {
    if (_failed || _failurePending) return;
    _failurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _failurePending = false;
      });
    });
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
      if (!mounted) return;
      setState(() {
        _failed = false;
        _revision++;
      });
    } catch (_) {
      // Keep the recovery action available if refreshing the tool also fails.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Widget _recovery(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 32,
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retrying ? null : _retry,
              icon: const Icon(Icons.refresh),
              label: Text(appTr('Retry')),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_failed) return _recovery(context);
    try {
      return _RenderRecoveryScope(
        recovery: this,
        child: KeyedSubtree(
          key: ValueKey(_revision),
          child: widget.builder(context),
        ),
      );
    } catch (_) {
      _failed = true;
      return _recovery(context);
    }
  }
}

class _RenderRecoveryScope extends InheritedWidget {
  const _RenderRecoveryScope({required this.recovery, required super.child});
  final _ToolRenderBoundaryState recovery;

  @override
  bool updateShouldNotify(_RenderRecoveryScope oldWidget) =>
      recovery != oldWidget.recovery;
}

class _RenderFailureSlot extends StatelessWidget {
  const _RenderFailureSlot({required this.details, required this.fallback});
  final FlutterErrorDetails details;
  final ErrorWidgetBuilder fallback;

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_RenderRecoveryScope>();
    if (scope == null) return fallback(details);
    scope.recovery.captureFailure();
    return const SizedBox.shrink();
  }
}
