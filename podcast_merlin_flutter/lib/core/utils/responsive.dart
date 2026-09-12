import 'package:flutter/material.dart';

/// Screen size breakpoints following Material 3 layout guidelines.
class ResponsiveBreakpoints {
  const ResponsiveBreakpoints._();

  /// Maximum width for compact / mobile screens (phones, narrow windows)
  static const double compact = 600.0;

  /// Maximum width for medium screens (tablets, half-screen windows)
  static const double medium = 900.0;

  /// Width threshold for switching between bottom navigation and navigation rail
  static const double desktopNavRail = 768.0;
}

/// Convenience extension on BuildContext to query device sizing and breakpoints.
extension ResponsiveContext on BuildContext {
  /// Screen size of the current media query.
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Current screen width.
  double get screenWidth => screenSize.width;

  /// Current screen height.
  double get screenHeight => screenSize.height;

  /// Returns true if the width is less than 600px (mobile portrait, narrow window).
  bool get isCompact => screenWidth < ResponsiveBreakpoints.compact;

  /// Returns true if the width is between 600px and 899px (tablet, foldable).
  bool get isMedium =>
      screenWidth >= ResponsiveBreakpoints.compact && screenWidth < ResponsiveBreakpoints.medium;

  /// Returns true if the width is 900px or greater (desktop, large tablet landscape).
  bool get isExpanded => screenWidth >= ResponsiveBreakpoints.medium;

  /// Returns true if the width is 768px or greater, suitable for NavigationRail.
  bool get isDesktopNav => screenWidth >= ResponsiveBreakpoints.desktopNavRail;
}

/// A widget builder that supplies whether the current layout constraint is compact.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, BoxConstraints constraints, bool isCompact) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < ResponsiveBreakpoints.compact;
        return builder(context, constraints, isCompact);
      },
    );
  }
}
