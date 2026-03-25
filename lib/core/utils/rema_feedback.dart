import 'package:flutter/material.dart';

void showRemaMessage(
  BuildContext context,
  String message, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: label != null && onAction != null
            ? SnackBarAction(label: label, onPressed: onAction)
            : null,
      ),
    );
}