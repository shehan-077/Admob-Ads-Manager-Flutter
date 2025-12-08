import 'package:flutter/material.dart';

class LoadingOverlay {
  Color? _tintColor;

  void setColor(Color color) {
    _tintColor = color;
  }

  OverlayEntry _buildEntry() {
    return OverlayEntry(
      builder: (context) {
        return ColoredBox(
          color: (_tintColor ?? Colors.black54).withValues(alpha: 0.6),
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  OverlayEntry? _currentEntry;

  void show(BuildContext context) {
    if (_currentEntry != null) return;
    final overlay = Overlay.of(context);
    _currentEntry = _buildEntry();
    overlay.insert(_currentEntry!);
  }

  void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
