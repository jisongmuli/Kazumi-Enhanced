import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:window_manager/window_manager.dart';

/// App-owned Windows controls, including an exit route from native fullscreen.
class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key});

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _fullscreen = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_readFullscreen());
  }

  Future<void> _readFullscreen() async {
    try {
      final fullscreen = await windowManager.isFullScreen();
      if (mounted && fullscreen != _fullscreen) {
        setState(() => _fullscreen = fullscreen);
      }
    } catch (_) {
      // Native state can be unavailable during host-only UI rendering.
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullscreen = false);
  }

  @override
  void onWindowFocus() => unawaited(_readFullscreen());

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(context: context, message: '窗口操作失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFullscreen() => _perform(() async {
    final fullscreen = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(fullscreen);
    if (mounted) setState(() => _fullscreen = fullscreen);
  });

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget button(
      String tooltip,
      IconData icon,
      VoidCallback action, {
      bool close = false,
    }) => IconButton(
      tooltip: tooltip,
      onPressed: _busy ? null : action,
      icon: Icon(icon, size: 19),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(44, 40)),
        minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => close && states.contains(WidgetState.hovered)
              ? Colors.white
              : colors.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? close
                    ? const Color(0xffe5484d)
                    : colors.onSurface.withValues(alpha: 0.07)
              : Colors.transparent,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colors.outlineVariant,
        ),
        button(
          '最小化',
          Icons.remove_rounded,
          () => _perform(windowManager.minimize),
        ),
        button(
          _fullscreen ? '退出全屏' : '全屏',
          _fullscreen
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          _toggleFullscreen,
        ),
        // Use the native close signal so the existing exit/tray preference still applies.
        button(
          '关闭窗口',
          Icons.close_rounded,
          () => _perform(windowManager.close),
          close: true,
        ),
      ],
    );
  }
}
