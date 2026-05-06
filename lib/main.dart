import 'package:flutter/material.dart';

import 'screens/analytics_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_settings.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  await NotificationService.instance.init();
  runApp(const TimeTrackerApp());
}

// ─── Theme factories ─────────────────────────────────────────────────────────

ThemeData _buildTheme({required bool dark}) {
  final cs = dark ? _darkScheme : _lightScheme;

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: dark
          ? const Color(0xFF3A3A3A)
          : const Color(0xFFE8E8E8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.onPrimary;
          return cs.onSurfaceVariant;
        }),
      ),
    ),
    chipTheme: ChipThemeData(
      selectedColor: cs.primary,
      backgroundColor:
          dark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
      side: BorderSide.none,
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1A1A1A) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

// ─── Light color scheme ───────────────────────────────────────────────────────

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF2D2D2D),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF0F0F0),
  onPrimaryContainer: Color(0xFF1A1A1A),
  secondary: Color(0xFF555555),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE8E8E8),
  onSecondaryContainer: Color(0xFF1A1A1A),
  tertiary: Color(0xFF888888),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF5F5F5),
  onTertiaryContainer: Color(0xFF1A1A1A),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF1A1A1A),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF8F8F8),
  surfaceContainer: Color(0xFFF5F5F5),
  surfaceContainerHigh: Color(0xFFF0F0F0),
  surfaceContainerHighest: Color(0xFFE8E8E8),
  onSurfaceVariant: Color(0xFF757575),
  outline: Color(0xFF9E9E9E),
  outlineVariant: Color(0xFFDDDDDD),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  inverseSurface: Color(0xFF2D2D2D),
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Color(0xFFD0D0D0),
  scrim: Color(0xFF000000),
  shadow: Color(0xFF000000),
);

// ─── Dark color scheme ────────────────────────────────────────────────────────

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE0E0E0),       // light gray — buttons, FAB, accents
  onPrimary: Color(0xFF111111),
  primaryContainer: Color(0xFF2A2A2A),
  onPrimaryContainer: Color(0xFFE0E0E0),
  secondary: Color(0xFFAAAAAA),
  onSecondary: Color(0xFF1A1A1A),
  secondaryContainer: Color(0xFF2A2A2A),
  onSecondaryContainer: Color(0xFFCCCCCC),
  tertiary: Color(0xFF888888),
  onTertiary: Color(0xFF1A1A1A),
  tertiaryContainer: Color(0xFF1E1E1E),
  onTertiaryContainer: Color(0xFFCCCCCC),
  surface: Color(0xFF111111),       // near-black background
  onSurface: Color(0xFFE8E8E8),
  surfaceContainerLowest: Color(0xFF0A0A0A),
  surfaceContainerLow: Color(0xFF161616),
  surfaceContainer: Color(0xFF1A1A1A),
  surfaceContainerHigh: Color(0xFF202020),
  surfaceContainerHighest: Color(0xFF2A2A2A),
  onSurfaceVariant: Color(0xFF9E9E9E),
  outline: Color(0xFF555555),
  outlineVariant: Color(0xFF333333),
  error: Color(0xFFCF6679),
  onError: Color(0xFF111111),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFFFB4AB),
  inverseSurface: Color(0xFFE8E8E8),
  onInverseSurface: Color(0xFF1A1A1A),
  inversePrimary: Color(0xFF2D2D2D),
  scrim: Color(0xFF000000),
  shadow: Color(0xFF000000),
);

// ─── App ─────────────────────────────────────────────────────────────────────

class TimeTrackerApp extends StatelessWidget {
  const TimeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Time Tracker',
          debugShowCheckedModeBanner: false,
          themeMode: AppSettings.instance.themeMode,
          theme: _buildTheme(dark: false),
          darkTheme: _buildTheme(dark: true),
          home: const MainShell(),
        );
      },
    );
  }
}

// ─── Shell ────────────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  late final ValueNotifier<int> _analyticsRefreshNotifier;
  late final ValueNotifier<int> _goalsRefreshNotifier;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _analyticsRefreshNotifier = ValueNotifier<int>(0);
    _goalsRefreshNotifier = ValueNotifier<int>(0);
    _screens = [
      const HomeScreen(),
      AnalyticsScreen(refreshNotifier: _analyticsRefreshNotifier),
      GoalsScreen(refreshNotifier: _goalsRefreshNotifier),
      const SettingsScreen(),
    ];
  }

  @override
  void dispose() {
    _analyticsRefreshNotifier.dispose();
    _goalsRefreshNotifier.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == 1) _analyticsRefreshNotifier.value++;
    if (index == 2) _goalsRefreshNotifier.value++;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onTabSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer_rounded),
            label: 'Таймер',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Аналитика',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Цели',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
