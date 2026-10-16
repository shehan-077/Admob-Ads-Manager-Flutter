import 'package:flutter/material.dart';

class LoadingOverlay {
  Color? _tintColor;
  OverlayEntry? _currentEntry;

  void setColor(Color color) {
    _tintColor = color;
  }

  OverlayEntry _buildEntry() {
    return OverlayEntry(
      builder: (_) {
        return AbsorbPointer(
          absorbing: true,
          child: ColoredBox(
            color: (_tintColor ?? Colors.black54).withValues(alpha: 0.6),
            child: const Center(child: CircularProgressIndicator()),
          ),
        );
      },
    );
  }

  /// Shows the overlay. Never throws: if [context] is unmounted or has no
  /// [Overlay] ancestor the ad simply loads without a spinner.
  void show(BuildContext context) {
    if (_currentEntry != null || !context.mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = _buildEntry();
    _currentEntry = entry;
    overlay.insert(entry);
  }

  void hide() {
    final entry = _currentEntry;
    _currentEntry = null;
    if (entry == null) return;

    try {
      entry.remove();
    } catch (e) {
      debugPrint('Loading overlay could not be removed: $e');
    }
  }

  bool get isShowing => _currentEntry != null;
}
