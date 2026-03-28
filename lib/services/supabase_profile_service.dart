/// Profile row in Supabase `public.profiles`.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

class SupabaseProfileService {
  SupabaseProfileService({SupabaseClient? client})
      : _client = client ?? SupabaseClientProvider.instance.client;

  final SupabaseClient _client;

  /// Upsert the signed-in user's profile row after phone OTP verification.
  Future<void> upsertCurrentUserProfile() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return;

    final Map<String, dynamic> row = <String, dynamic>{
      'id': user.id,
      'phone': user.phone,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final String? email = user.email;
    if (email != null && email.isNotEmpty) {
      row['email'] = email;
    }

    await _client.from('profiles').upsert(
          row,
          onConflict: 'id',
        );
  }
}
