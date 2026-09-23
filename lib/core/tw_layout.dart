import 'package:flutter/material.dart';

/// Shared breakpoints and adaptive layout utilities for Cosmic Trader.
class TWLayout {
  TWLayout._();

  /// Minimum width to consider a screen "large" (tablet/desktop).
  static const double largeScreenMinWidth = 600.0;

  /// Minimum width for extra-large layouts (wide desktop).
  static const double extraLargeScreenMinWidth = 900.0;

  /// Maximum comfortable width for forms, text blocks, and single-column content.
  static const double maxContentWidth = 800.0;

  /// Width allocated to the navigation sidebar on large screens.
  static const double sidebarWidth = 250.0;

  /// Width allocated to the navigation rail on medium screens.
  static const double railWidth = 72.0;

  /// Returns true if the current constraints indicate a large screen.
  static bool isLargeScreen(BuildContext context) {
    return MediaQuery.sizeOf(context).width > largeScreenMinWidth;
  }

  /// Returns true if the current constraints indicate an extra-large screen.
  static bool isExtraLargeScreen(BuildContext context) {
    return MediaQuery.sizeOf(context).width > extraLargeScreenMinWidth;
  }

  /// Builds a layout that adapts between small and large screen variants.
  static Widget buildAdaptive({
    required Widget smallScreen,
    required Widget largeScreen,
    double? breakpoint,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bp = breakpoint ?? largeScreenMinWidth;
        if (constraints.maxWidth > bp) {
          return largeScreen;
        }
        return smallScreen;
      },
    );
  }

  /// Wraps a widget in a centered, width-constrained container to prevent
  /// unnatural stretching on large screens.
  static Widget constrainContentWidth(Widget child, {double? maxWidth}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? maxContentWidth),
        child: child,
      ),
    );
  }
}
