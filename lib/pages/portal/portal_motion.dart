import 'package:flutter/material.dart';

abstract final class PortalMotion {
  static Duration duration(BuildContext context, [int milliseconds = 220]) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
  static const curve = Curves.easeOutCubic;
}

/// Short entrance motion only on insertion, never on every feed update.
class PortalReveal extends StatelessWidget {
  const PortalReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: PortalMotion.duration(context, 280),
    curve: PortalMotion.curve,
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - value)),
        child: child,
      ),
    ),
  );
}

/// Meaningful placeholder geometry, with no constantly running card tickers.
class PortalSkeleton extends StatelessWidget {
  const PortalSkeleton({super.key, this.radius = 12});
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffe7edf6), Color(0xfff0f4fa), Color(0xffe5ebf4)],
        ),
      ),
    ),
  );
}

class PortalPosterSkeleton extends StatelessWidget {
  const PortalPosterSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(child: PortalSkeleton()),
      const SizedBox(height: 12),
      const SizedBox(height: 13, width: 120, child: PortalSkeleton(radius: 4)),
      const SizedBox(height: 7),
      const SizedBox(height: 10, width: 80, child: PortalSkeleton(radius: 4)),
      const SizedBox(height: 6),
    ],
  );
}
