import 'package:flutter/material.dart';

class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  // Helpers for LayoutBuilder constraints
  static bool isMobileByWidth(double width) => width < mobileBreakpoint;
  static bool isTabletByWidth(double width) => width >= mobileBreakpoint && width < tabletBreakpoint;
  static bool isDesktopByWidth(double width) => width >= tabletBreakpoint;

  static double getCardWidth(double constraintsWidth) {
    if (isDesktopByWidth(constraintsWidth)) return 440.0;
    if (isTabletByWidth(constraintsWidth)) return 420.0;
    return constraintsWidth; // Full width on mobile
  }
}
