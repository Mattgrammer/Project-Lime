import 'package:delightful_toast/delight_toast.dart';
import 'package:delightful_toast/toast/components/toast_card.dart';
import 'package:delightful_toast/toast/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class NotificationHelper {
  static void showSuccess(BuildContext context, String message) {
    DelightToastBar(
      autoDismiss: true,
      animationDuration: const Duration(milliseconds: 300),
      snackbarDuration: const Duration(milliseconds: 3000),
      position: DelightSnackbarPosition.top,
      builder: (context) => ToastCard(
        leading: Icon(
          Icons.check_circle_outline,
          size: 28,
          color: HexColor("#116754"),
        ),
        title: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),
    ).show(context);
  }

  static void showError(BuildContext context, String message) {
    DelightToastBar(
      autoDismiss: true,
      animationDuration: const Duration(milliseconds: 300),
      snackbarDuration: const Duration(milliseconds: 3000),
      position: DelightSnackbarPosition.top,
      builder: (context) => ToastCard(
        leading: const Icon(
          Icons.error_outline,
          size: 28,
          color: Colors.redAccent,
        ),
        title: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),
    ).show(context);
  }

  static void showInfo(BuildContext context, String message) {
    DelightToastBar(
      autoDismiss: true,
      animationDuration: const Duration(milliseconds: 300),
      snackbarDuration: const Duration(milliseconds: 3000),
      position: DelightSnackbarPosition.top,
      builder: (context) => ToastCard(
        leading: Icon(
          Icons.info_outline,
          size: 28,
          color: HexColor("#0F4C7F"),
        ),
        title: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),
    ).show(context);
  }
}
