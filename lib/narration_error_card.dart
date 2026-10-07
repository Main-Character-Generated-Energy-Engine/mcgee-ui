import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Kept scrollable and selectable for small phones and clipboard restrictions.
class NarrationErrorCard extends StatefulWidget {
  const NarrationErrorCard({
    super.key,
    required this.message,
    required this.report,
    this.onReturnToSelection,
  });

  final String message;
  final String report;
  final VoidCallback? onReturnToSelection;

  @override
  State<NarrationErrorCard> createState() => _NarrationErrorCardState();
}

class _NarrationErrorCardState extends State<NarrationErrorCard> {
  bool _copied = false;
  bool _copyFailed = false;

  @override
  void didUpdateWidget(NarrationErrorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != widget.report) {
      _copied = false;
      _copyFailed = false;
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: '${widget.message}\n\n${widget.report}'),
      );
      if (!mounted) return;
      setState(() {
        _copied = true;
        _copyFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copied = false;
        _copyFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff572c2c),
      borderRadius: BorderRadius.circular(12),
      elevation: 8,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              widget.message,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('copy-narration-error'),
                  onPressed: _copy,
                  icon: Icon(_copied ? Icons.check : Icons.copy),
                  label: Text(_copied ? 'Copied' : 'Copy error details'),
                ),
                if (widget.onReturnToSelection != null)
                  TextButton(
                    key: const ValueKey('return-to-narration-selection'),
                    onPressed: widget.onReturnToSelection,
                    child: const Text('Back to narration selection'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _copyFailed
                  ? 'Copy was blocked. Press and hold the details below to select and copy them.'
                  : _copied
                  ? 'Error details copied. Paste them into a message to the app owner.'
                  : 'Send these error details to the app owner for help.',
              semanticsLabel: _copied ? 'Error details copied' : null,
            ),
            const SizedBox(height: 8),
            SelectableText(
              widget.report,
              key: const ValueKey('narration-error-details'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
