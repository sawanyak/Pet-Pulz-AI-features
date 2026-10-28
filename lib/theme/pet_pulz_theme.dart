import 'package:flutter/material.dart';

/// Central theme and design system matching the Pet Pulz visual identity.
class PetPulzTheme {
  // Brand colors extracted from Pet Pulz app screenshots
  static const Color primaryPurple = Color(0xFF5B4BD8);
  static const Color primaryGradientStart = Color(0xFF4F3FC9);
  static const Color primaryGradientEnd = Color(0xFF6C5CE7);
  
  static const Color bgGradientTop = Color(0xFFEAE5F9);
  static const Color bgGradientMid = Color(0xFFF8EEF9);
  static const Color bgGradientBottom = Color(0xFFEBF2FC);
  
  static const Color activeNavHighlight = Color(0xFFDDD5FB);
  static const Color navBackground = Color(0xFFF3EEFC);
  
  static const Color pillBg = Color(0xFFEDE8FF);
  static const Color pillText = Color(0xFF5B4BD8);
  
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1E1A42);
  static const Color textMuted = Color(0xFF6C688E);

  static ThemeData get themeData {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryPurple,
      primary: primaryPurple,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: bgGradientTop,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryPurple),
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 2,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryPurple,
          side: const BorderSide(color: primaryPurple, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE6E0F8), width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: pillBg,
        selectedColor: primaryPurple,
        secondarySelectedColor: primaryPurple,
        labelStyle: const TextStyle(color: textDark, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFDDD5FB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE6E0F8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primaryPurple, width: 2),
        ),
      ),
    );
  }
}

/// A wrapper widget that applies the soft Pet Pulz pastel gradient background.
class PetPulzBackground extends StatelessWidget {
  const PetPulzBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PetPulzTheme.bgGradientTop,
            PetPulzTheme.bgGradientMid,
            PetPulzTheme.bgGradientBottom,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Pet Pulz custom header bar with menu (or back arrow) and logo.
class PetPulzHeader extends StatelessWidget implements PreferredSizeWidget {
  const PetPulzHeader({
    super.key,
    this.onMenuPressed,
    this.onBackPressed,
    this.trailing,
  });

  final VoidCallback? onMenuPressed;

  /// When set, a back arrow is shown instead of the menu icon.
  final VoidCallback? onBackPressed;

  /// Shown at the right edge (a 48px-wide widget keeps the logo centred).
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (onBackPressed != null)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: PetPulzTheme.primaryPurple, size: 28),
                onPressed: onBackPressed,
                tooltip: 'Back',
              )
            else
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: PetPulzTheme.primaryPurple, size: 28),
                onPressed: onMenuPressed ?? () {},
                tooltip: 'Menu',
              ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      color: PetPulzTheme.primaryPurple,
                      size: 30,
                    ),
                    Container(
                      width: 2,
                      height: 16,
                      color: PetPulzTheme.primaryPurple,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'Pet',
                        style: TextStyle(color: PetPulzTheme.primaryPurple),
                      ),
                      TextSpan(
                        text: 'Pulz',
                        style: TextStyle(color: PetPulzTheme.textDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Mirrors the leading icon's width so the logo stays centred.
            trailing ?? const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

/// Pet Pulz bottom navigation bar with active highlights and rounded design.
class PetPulzBottomNav extends StatelessWidget {
  const PetPulzBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'HOME', 'Home'),
      (Icons.health_and_safety_outlined, 'HEALTH', 'Photo health check'),
      (Icons.auto_awesome_outlined, 'STUDIO', 'Photo studio'),
      (Icons.pets_rounded, 'MY PETS', 'Your cat\'s profile'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: PetPulzTheme.navBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x154F3FC9),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final isSelected = index == currentIndex;
            final icon = items[index].$1;
            final label = items[index].$2;
            final tooltip = items[index].$3;

            return Tooltip(
              message: tooltip,
              child: InkWell(
              onTap: () => onTap(index),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? PetPulzTheme.activeNavHighlight : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        icon,
                        color: isSelected ? PetPulzTheme.primaryPurple : PetPulzTheme.textMuted,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? PetPulzTheme.primaryPurple : PetPulzTheme.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            );
          }),
        ),
      ),
    );
  }
}

/// Reusable Pill Tag (e.g. "✨ THE ULTIMATE SANCTUARY").
class PetPulzPillBadge extends StatelessWidget {
  const PetPulzPillBadge({
    super.key,
    required this.text,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });

  final String text;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? PetPulzTheme.primaryPurple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor ?? Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: textColor ?? Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable Card component matching Pet Pulz rounded white surfaces.
class PetPulzCard extends StatelessWidget {
  const PetPulzCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.gradient,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Colors.white) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: gradient == null
            ? const [
                BoxShadow(
                  color: Color(0x104A3BB5),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
