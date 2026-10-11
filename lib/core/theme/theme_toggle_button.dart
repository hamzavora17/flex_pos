import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// A universal navbar button to toggle between Light and Dark mode across the application.
class ThemeToggleButton extends StatelessWidget {
  final Color? color;
  final double iconSize;

  const ThemeToggleButton({
    super.key,
    this.color,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, currentMode, _) {
        final isDark = currentMode == ThemeMode.dark;
        return Tooltip(
          message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: iconSize,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: isDark
                    ? Icon(
                        Icons.wb_sunny_rounded,
                        key: const ValueKey('sun'),
                        color: color ?? Colors.amber,
                        size: iconSize,
                      )
                    : Icon(
                        Icons.nightlight_round,
                        key: const ValueKey('moon'),
                        color: color ?? Colors.white,
                        size: iconSize,
                      ),
              ),
              onPressed: () => ThemeController.instance.toggleTheme(),
            ),
          ),
        );
      },
    );
  }
}
