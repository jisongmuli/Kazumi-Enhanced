import 'package:flutter/material.dart';
import 'package:kazumi/services/storage/storage.dart';

class PortalStyle {
  static const versionKey = SettingKey<int>(
    'portalLayoutVersion',
    0,
    group: SettingGroup.interface,
  );
  static Future<void> initializePreferences() async {
    if (GStorage.getSetting(versionKey) >= 1) return;
    await GStorage.putSetting(SettingsKeys.themeMode, 'light');
    await GStorage.putSetting(SettingsKeys.themeColor, 'ff2463ff');
    await GStorage.putSetting(SettingsKeys.useDynamicColor, false);
    if (GStorage.getSetting(SettingsKeys.defaultStartupPage) ==
        '/tab/popular/') {
      await GStorage.putSetting(SettingsKeys.defaultStartupPage, '/tab/home/');
    }
    await GStorage.putSetting(versionKey, 1);
  }

  static const blue = Color(0xff2463ff);
  static const background = Color(0xfff5f7fb);
  static const ink = Color(0xff172033);
  static const muted = Color(0xff7b8497);
  static ThemeData theme(ThemeData parent) => ThemeData(
    useMaterial3: true,
    fontFamily: parent.textTheme.bodyMedium?.fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
        ).copyWith(
          primary: blue,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainer: background,
          surfaceContainerLow: const Color(0xfff8f9fc),
        ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: parent.textTheme.bodyMedium?.fontFamily,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xffeff3fa),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide.none,
      ),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: blue,
      linearTrackColor: Color(0xffe2e8f4),
    ),
  );
}
