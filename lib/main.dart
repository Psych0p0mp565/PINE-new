/// PINE - Pest Identification on Native Environments
///
/// Offline-first Android mobile application for detecting tiny agricultural pests
/// (e.g., mealybugs) on plant leaves using YOLO 11 TensorFlow Lite.
/// Cloud sync via Supabase; offline persistence via local DB.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_state.dart';
import 'core/service_locator.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'services/biometric_service.dart';
import 'services/camera_service.dart';
import 'services/database_service.dart';
import 'services/geo_fence_service.dart';
import 'services/geo_service.dart';
import 'services/image_storage_service.dart';
import 'services/inference_service.dart';
import 'screens/terms_acceptance_screen.dart';
import 'screens/intro_flow_screen.dart';
import 'screens/main_dashboard_screen.dart';
import 'screens/fields_list_screen.dart';
import 'screens/disease_info_screen.dart';
import 'screens/location_selector_screen.dart';
import 'screens/permission_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/faq_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/nickname_prompt_screen.dart';
import 'screens/captured_photos_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/config_required_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase. (Provide via `--dart-define`).
  final bool supabaseOk = await SupabaseClientProvider.instance.tryInitFromEnv();

  // Register core services for simple dependency injection.
  final ServiceLocator sl = ServiceLocator.instance;
  sl
    ..registerSingleton<BiometricService>(BiometricService())
    ..registerSingleton<CameraService>(CameraService())
    ..registerSingleton<InferenceService>(InferenceService())
    ..registerSingleton<DatabaseService>(DatabaseService())
    ..registerSingleton<GeoService>(GeoService())
    ..registerSingleton<GeoFenceService>(GeoFenceService())
    ..registerSingleton<ImageStorageService>(ImageStorageService());

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..loadPreferences(),
      child: MyApp(supabaseConfigured: supabaseOk),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  static Future<bool> _checkTermsAccepted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool termsAccepted = prefs.getBool('terms_accepted') ?? false;
    final bool? privacyAcceptedRaw = prefs.getBool('privacy_accepted');
    // Backward compatibility: older app versions only stored `terms_accepted`.
    final bool privacyAccepted = privacyAcceptedRaw ?? termsAccepted;
    return termsAccepted && privacyAccepted;
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseConfigured) {
      return MaterialApp(
        title: 'PINYA-PIC',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: ConfigRequiredScreen(
          message: (SupabaseClientProvider.instance.initError ?? '')
              .toString(),
        ),
      );
    }
    return MaterialApp(
      title: 'PINYA-PIC',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: <String, WidgetBuilder>{
        '/': (BuildContext context) => FutureBuilder<bool>(
              future: _checkTermsAccepted(),
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.data == true) {
                  return const IntroFlowScreen();
                }
                return const TermsAcceptanceScreen();
              },
            ),
        '/login': (BuildContext context) => const LoginScreen(),
        '/register': (BuildContext context) => const RegisterScreen(),
        '/forgot-password': (BuildContext context) =>
            const ForgotPasswordScreen(),
        '/dashboard': (BuildContext context) => const MainDashboardScreen(),
        '/fields': (BuildContext context) => const FieldsListScreen(),
        '/diseases': (BuildContext context) => const DiseaseInfoScreen(),
        '/camera': (BuildContext context) => const PhotoSourcePicker(),
        '/captured': (BuildContext context) => const CapturedPhotosScreen(),
        '/location': (BuildContext context) => const LocationSelectorScreen(),
        '/settings': (BuildContext context) => const SettingsScreen(),
        '/profile': (BuildContext context) => const ProfileScreen(),
        '/notifications': (BuildContext context) => const NotificationsScreen(),
        '/faq': (BuildContext context) => const FaqScreen(),
        '/privacy': (BuildContext context) => const PrivacyScreen(),
        '/terms': (BuildContext context) => const TermsScreen(),
        '/feedback': (BuildContext context) => const FeedbackScreen(),
        '/nickname-prompt': (BuildContext context) =>
            const NicknamePromptScreen(),
      },
    );
  }
}
