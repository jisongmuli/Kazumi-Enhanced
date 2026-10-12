import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart';
import 'package:kazumi/pages/portal/portal_theme.dart';
import 'package:kazumi/pages/portal/portal_motion.dart';

/// Presentational header: every visible control is provided an actual action.
class PortalHeader extends StatefulWidget {
  const PortalHeader({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
    required this.onSearch,
    required this.onHistory,
    required this.onMore,
    this.onClose,
  });
  final int selectedIndex;
  final ValueChanged<int> onNavigate;
  final ValueChanged<String> onSearch;
  final VoidCallback onHistory;
  final ValueChanged<String> onMore;
  final VoidCallback? onClose;
  static const destinations = [
    (5, '首页'),
    (0, '动漫'),
    (4, '影视'),
    (6, '短剧'),
    (7, 'YouTube'),
    (3, '我的'),
  ];
  @override
  State<PortalHeader> createState() => _PortalHeaderState();
}

class _PortalHeaderState extends State<PortalHeader> {
  final input = TextEditingController();
  void submit() {
    final value = input.text.trim();
    if (value.isNotEmpty) {
      FocusScope.of(context).unfocus();
      widget.onSearch(value);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1050;
          final brand = DragToMoveArea(
            child: InkWell(
              onTap: () => widget.onNavigate(5),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Text(
                  'Kazumi',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: PortalStyle.blue,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
          );
          final navigation = SizedBox(
            width: 74.0 * PortalHeader.destinations.length,
            height: 58,
            child: Stack(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, label) in PortalHeader.destinations)
                      TextButton(
                        onPressed: () => widget.onNavigate(index),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(74, 58),
                          maximumSize: const Size(74, 58),
                          padding: EdgeInsets.zero,
                          foregroundColor: widget.selectedIndex == index
                              ? PortalStyle.blue
                              : PortalStyle.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: PortalMotion.duration(context, 180),
                              style: Theme.of(context).textTheme.labelLarge!
                                  .copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: widget.selectedIndex == index
                                        ? PortalStyle.blue
                                        : PortalStyle.ink,
                                  ),
                              child: Text(label),
                            ),
                            const SizedBox(height: 7),
                            const SizedBox(height: 3),
                          ],
                        ),
                      ),
                  ],
                ),
                if (PortalHeader.destinations.any(
                  (d) => d.$1 == widget.selectedIndex,
                ))
                  AnimatedPositioned(
                    duration: PortalMotion.duration(context, 260),
                    curve: PortalMotion.curve,
                    left:
                        PortalHeader.destinations.indexWhere(
                              (d) => d.$1 == widget.selectedIndex,
                            ) *
                            74.0 +
                        24,
                    bottom: 5,
                    child: Container(
                      width: 26,
                      height: 3,
                      decoration: BoxDecoration(
                        color: PortalStyle.blue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          );
          final search = SizedBox(
            height: 40,
            child: TextField(
              key: const ValueKey('portal-global-search'),
              controller: input,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                hintText: '搜索番剧、电影、短剧',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: PortalStyle.muted,
                ),
                prefixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: submit,
                  icon: const Icon(Icons.search, size: 20),
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: input,
                  builder: (_, value, child) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: '清空输入',
                          onPressed: input.clear,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                ),
              ),
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide)
                TextButton.icon(
                  onPressed: widget.onHistory,
                  icon: const Icon(Icons.history, size: 20),
                  label: const Text('观看记录'),
                )
              else
                IconButton(
                  onPressed: widget.onHistory,
                  tooltip: '观看记录',
                  icon: const Icon(Icons.history),
                ),
              PopupMenuButton<String>(
                tooltip: '更多功能',
                onSelected: widget.onMore,
                icon: const Icon(Icons.more_horiz),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'timeline', child: Text('追番时间表')),
                  PopupMenuItem(value: 'collect', child: Text('我的追番')),
                  PopupMenuItem(value: 'sources', child: Text('片源目录')),
                  PopupMenuItem(value: 'search', child: Text('高级动漫搜索')),
                  PopupMenuItem(value: 'settings', child: Text('设置')),
                ],
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: '关闭窗口',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
            ],
          );
          if (wide) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  brand,
                  navigation,
                  const SizedBox(width: 20),
                  Expanded(child: search),
                  const SizedBox(width: 14),
                  actions,
                ],
              ),
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  brand,
                  Expanded(child: search),
                  actions,
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: navigation,
              ),
            ],
          );
        },
      ),
    ),
  );
}
