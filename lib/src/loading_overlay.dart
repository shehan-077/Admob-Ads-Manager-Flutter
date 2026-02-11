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
            color: (_tintColor ?? Colors.black54).withOpacity(0.6),
            child: const Center(child: CircularProgressIndicator()),
          ),
        );
      },
    );
  }

  void show(BuildContext context) {
    if (_currentEntry != null) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry = _buildEntry();
    overlay.insert(_currentEntry!);
  }

  void hide() {
    final entry = _currentEntry;
    _currentEntry = null;
    if (entry == null) return;

    try {
      entry.remove();
    } catch (_) {
      // ignore: already removed / route disposed
    }
  }

  bool get isShowing => _currentEntry != null;
}
