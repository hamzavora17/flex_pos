import 'dart:convert';
import 'package:flutter/material.dart';

import 'app_logo_controller.dart';

/// Reactive widget that displays the current application logo and automatically
/// re-renders whenever the global system logo setting is updated.
class AppLogoWidget extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallbackWidget;

  const AppLogoWidget({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLogoController.instance,
      builder: (context, logoPath, _) {
        return _renderLogoImage(logoPath);
      },
    );
  }

  Widget _renderLogoImage(String path) {
    final defaultFallback = fallbackWidget ??
        Icon(
          Icons.storefront_rounded,
          size: (height ?? width ?? 28),
          color: const Color(0xFF003366),
        );

    final trimmed = path.trim();

    if (trimmed.isEmpty || trimmed == AppLogoController.defaultLogoPath) {
      return Image.asset(
        AppLogoController.defaultLogoPath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => defaultFallback,
      );
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset(
          AppLogoController.defaultLogoPath,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => defaultFallback,
        ),
      );
    }

    if (trimmed.startsWith('data:image')) {
      try {
        final commaIndex = trimmed.indexOf(',');
        if (commaIndex != -1) {
          final base64Str = trimmed.substring(commaIndex + 1);
          final bytes = base64Decode(base64Str);
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => defaultFallback,
          );
        }
      } catch (_) {}
    }

    if (trimmed.startsWith('assets/')) {
      return Image.asset(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset(
          AppLogoController.defaultLogoPath,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => defaultFallback,
        ),
      );
    }

    // Default fallback
    return Image.asset(
      AppLogoController.defaultLogoPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => defaultFallback,
    );
  }
}
