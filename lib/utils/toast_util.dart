import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class ToastUtil {
  static void showSuccess(BuildContext context, String message) {
    _showToast(context, message, false);
  }

  static void showError(BuildContext context, String message) {
    _showToast(context, message, true);
  }

  static void _showToast(BuildContext context, String message, bool isError) {
    toastification.showCustom(
      context: context,
      autoCloseDuration: const Duration(seconds: 3),
      alignment: Alignment.topCenter,
      builder: (BuildContext context, ToastificationItem holder) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: isError
                  ? [Colors.red.shade50, Colors.red.shade100]
                  : [Colors.green.shade50, Colors.green.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: (isError ? Colors.red : Colors.green).withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
            border: Border.all(
              color: (isError ? Colors.red : Colors.green).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError ? Colors.red.shade900 : Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
