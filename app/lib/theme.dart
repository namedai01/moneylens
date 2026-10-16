import 'package:flutter/material.dart';

/// Money in / money out colors; read with `Theme.of(context).extension`.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  final Color income;
  final Color expense;
  final Color muted;
  final Color line;

  const MoneyColors({
    required this.income,
    required this.expense,
    required this.muted,
    required this.line,
  });

  static const light = MoneyColors(
    income: Color(0xFF13795B),
    expense: Color(0xFFB4232F),
    muted: Color(0xFF66707A),
    line: Color(0xFFDDE2E7),
  );

  static const dark = MoneyColors(
    income: Color(0xFF4CC59A),
    expense: Color(0xFFFF7A80),
    muted: Color(0xFF8D98A3),
    line: Color(0xFF2A333C),
  );

  /// Falls back to the defaults under a theme without the extension.
  static MoneyColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MoneyColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  MoneyColors copyWith({
    Color? income,
    Color? expense,
    Color? muted,
    Color? line,
  }) => MoneyColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    muted: muted ?? this.muted,
    line: line ?? this.line,
  );

  @override
  MoneyColors lerp(MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

const _font = 'BeVietnamPro';

/// Ink on cool paper; jade for money in, seal red for money out.
ThemeData moneyLensTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final paper = dark ? const Color(0xFF12171C) : const Color(0xFFF3F5F7);
  final surface = dark ? const Color(0xFF1A2128) : const Color(0xFFFFFFFF);
  final ink = dark ? const Color(0xFFE7ECEF) : const Color(0xFF17212B);
  final money = dark ? MoneyColors.dark : MoneyColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink,
    onPrimary: paper,
    secondary: money.income,
    onSecondary: paper,
    error: money.expense,
    onError: paper,
    errorContainer: dark ? const Color(0xFF3A1D21) : const Color(0xFFFBE9EA),
    onErrorContainer: dark ? const Color(0xFFFFD9DB) : const Color(0xFF5E0F16),
    tertiaryContainer: dark ? const Color(0xFF3A3020) : const Color(0xFFFFF3D6),
    onTertiaryContainer: dark
        ? const Color(0xFFFFE3A8)
        : const Color(0xFF5A4300),
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: money.muted,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    outline: money.muted,
    outlineVariant: money.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _font,
  );
  final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);

  return base.copyWith(
    scaffoldBackgroundColor: paper,
    extensions: [money],
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
        height: 1.1,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      bodySmall: text.bodySmall?.copyWith(color: money.muted, height: 1.4),
      labelMedium: text.labelMedium?.copyWith(color: money.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: money.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: money.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: money.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
