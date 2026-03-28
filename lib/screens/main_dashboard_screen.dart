// Modernized main dashboard: Home, Diagnose, My Fields, More with bottom nav.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../core/app_state.dart';
import '../core/map_tiles.dart';
import '../core/theme.dart';
import '../services/captured_photos_remote_sync.dart';
import '../services/database_service.dart';
import '../services/image_storage_service.dart';
import '../services/dashboard_stats_service.dart';
import '../widgets/capture_thumbnail.dart';
import 'disease_info_screen.dart';
import 'disease_detail_screen.dart';
import 'disease_by_category_screen.dart';
import 'educational_content_screen.dart';
import 'location_picker_screen.dart';
import 'permission_screens.dart';
import 'farm_details_screen.dart';
import 'field_detail_screen.dart';
import 'edit_field_screen.dart';
import '../widgets/online_required_dialog.dart';
import 'captured_photo_detail_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  /// 0=Home, 1=Diagnose, 2=My Fields, 3=More. Bottom bar has 5 items; index 2 is Scan (action).
  int _pageIndex = 0;

  int get _navIndex => _pageIndex <= 1 ? _pageIndex : _pageIndex + 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNickname());
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullCapturedPhotosFromCloud());
  }

  Future<void> _pullCapturedPhotosFromCloud() async {
    final int n =
        await CapturedPhotosRemoteSync().pullIntoLocalIfSignedIn();
    if (!mounted) return;
    if (n > 0) {
      context.read<AppState>().bumpCapturedPhotos();
    }
  }

  Future<void> _checkNickname() async {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final Map<String, dynamic>? row = await SupabaseClientProvider
          .instance.client
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      final String? displayName = row?['display_name'] as String?;
      if (!mounted) return;
      if (displayName == null || displayName.trim().isEmpty) {
        Navigator.pushNamed(context, '/nickname-prompt');
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Container(
                  color: AppTheme.backgroundLight,
                  child: IndexedStack(
                    index: _pageIndex,
                    children: const <Widget>[
                      _HomeTab(key: ValueKey<int>(0)),
                      _DiagnoseTab(key: ValueKey<int>(1)),
                      _MyFieldsTab(key: ValueKey<int>(2)),
                      _MoreTab(key: ValueKey<int>(3)),
                    ],
                  ),
                ),
              ),
            ),
            _buildBottomNav(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundDark,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _NavItem(
            icon: Icons.home_outlined,
            label: 'Home',
            selected: _navIndex == 0,
            onTap: () => setState(() => _pageIndex = 0),
          ),
          _NavItem(
            icon: Icons.shield_outlined,
            label: 'Diagnose',
            selected: _navIndex == 1,
            onTap: () => setState(() => _pageIndex = 1),
          ),
          _ScanButton(
            onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const PhotoSourcePicker()),
              );
            },
          ),
          _NavItem(
            icon: Icons.landscape_outlined,
            label: 'My Fields',
            selected: _navIndex == 3,
            onTap: () => setState(() => _pageIndex = 2),
          ),
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'More',
            selected: _navIndex == 4,
            onTap: () => setState(() => _pageIndex = 3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppTheme.primaryGreen : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppTheme.primaryGreen.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.document_scanner_outlined,
            color: Colors.white, size: 28),
      ),
    );
  }
}

// --- Home tab: logo, greeting, My Fields horizontal, Map Overview ---
class _HomeTab extends StatelessWidget {
  const _HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState appState = context.watch<AppState>();
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    final String user = SupabaseClientProvider
            .instance.client.auth.currentUser?.phone ??
        'User';
    final String greeting = _greeting();
    final bool fil = appState.isFilipino;
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.pest_control,
                          size: 32, color: AppTheme.primaryGreen),
                      SizedBox(width: 8),
                      Text(
                        'PINYA-PIC',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  appState.isLoggedIn ? '$greeting, $user' : greeting,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fil
                      ? 'Bantayan ang inyong pinya at panatilihing malusog ang taniman.'
                      : 'Monitor your pineapple crops and keep them healthy.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _HomeStatHeader(uid: uid, fil: fil),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              fil ? 'Mga Larawang Nai-save' : 'Saved Images',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: _RecentCapturesStrip(uid: uid, fil: fil),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              fil ? 'Aking Mga Sakahan' : 'My Fields',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        if (uid == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _EmptyFieldsMessage(),
            ),
          )
        else
          SliverToBoxAdapter(
            child: _FieldsHorizontalList(uid: uid),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              fil ? 'Preview ng Mapa: Polomolok' : 'Map Preview: Polomolok',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    FlutterMap(
                      options: const MapOptions(
                        initialCenter: LatLng(6.2167, 125.0667),
                        initialZoom: 11.8,
                        interactionOptions: InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapTiles.esriWorldImagery,
                          userAgentPackageName: 'com.pine.pine',
                          maxZoom: MapTiles.maxZoomSatellite.toDouble(),
                          maxNativeZoom: MapTiles.maxZoomSatellite,
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.36),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            if (!await ensureOnline(context)) return;
                            if (!context.mounted) return;
                            Navigator.push<Object?>(
                              context,
                              MaterialPageRoute<Object?>(
                                builder: (_) =>
                                    const LocationPickerScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Polomolok, South Cotabato',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () async {
                              if (!await ensureOnline(context)) return;
                              if (!context.mounted) return;
                              Navigator.push<Object?>(
                                context,
                                MaterialPageRoute<Object?>(
                                  builder: (_) => const LocationPickerScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(fil ? 'Buksan' : 'Open'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _HomeStatHeader extends StatelessWidget {
  const _HomeStatHeader({required this.uid, required this.fil});

  final String? uid;
  final bool fil;

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseClientProvider.instance.client
          .from('fields')
          .stream(primaryKey: const <String>['id'])
          .eq('user_id', uid!),
      builder: (BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        final fieldsCount = snapshot.data?.length ?? 0;
        return Row(
          children: [
            Expanded(
              child: _HomeMiniStat(
                icon: Icons.landscape_outlined,
                label: fil ? 'Kabuuang sakahan' : 'Total fields',
                value: '$fieldsCount',
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: _HomeMiniStat(
                icon: Icons.map_outlined,
                label: 'Region',
                value: 'Polomolok',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeMiniStat extends StatelessWidget {
  const _HomeMiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentCapturesStrip extends StatefulWidget {
  const _RecentCapturesStrip({required this.uid, required this.fil});

  final String? uid;
  final bool fil;

  @override
  State<_RecentCapturesStrip> createState() => _RecentCapturesStripState();
}

class _RecentCapturesStripState extends State<_RecentCapturesStrip> {
  final DatabaseService _db = DatabaseService();
  final ImageStorageService _images = ImageStorageService();

  @override
  void initState() {
    super.initState();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    await _db.initialize();
    if (widget.uid == null) return const <Map<String, dynamic>>[];
    return _db.getCapturedPhotos(limit: 12, userId: widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when new captures are saved locally.
    context.select<AppState, int>((s) => s.capturedPhotosRevision);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 108,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return Container(
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              widget.fil
                  ? 'Wala pang nai-save na larawan.'
                  : 'No saved captures yet.',
              style: const TextStyle(color: AppTheme.textMedium),
            ),
          );
        }
        return SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final row = rows[i];
              final int id = (row['id'] as num?)?.toInt() ?? -1;
              final String? localPath = row['local_image_path'] as String?;
              final String? remoteUrl = row['remote_image_url'] as String?;
              final bool canExpand = id >= 0 &&
                  ((remoteUrl != null && remoteUrl.trim().isNotEmpty) ||
                      (localPath != null &&
                          localPath.isNotEmpty &&
                          localPath != DatabaseService.remoteOnlyLocalPath));
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: !canExpand
                    ? null
                    : () async {
                        File? file;
                        if (localPath != null &&
                            localPath != DatabaseService.remoteOnlyLocalPath) {
                          file = await _images.getImageFile(localPath);
                        }
                        if (!context.mounted) return;
                        if (file == null &&
                            (remoteUrl == null || remoteUrl.isEmpty)) {
                          return;
                        }
                        await showDialog<void>(
                          context: context,
                          builder: (BuildContext dialogContext) {
                            return Dialog(
                              insetPadding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Stack(
                                  children: <Widget>[
                                    AspectRatio(
                                      aspectRatio: 1,
                                      child: InteractiveViewer(
                                        minScale: 1,
                                        maxScale: 4,
                                        child: file != null
                                            ? Image.file(
                                                file,
                                                fit: BoxFit.cover,
                                              )
                                            : Image.network(
                                                remoteUrl!,
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: IconButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              Colors.black.withValues(alpha: 0.45),
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                    Positioned(
                                      left: 12,
                                      right: 12,
                                      bottom: 12,
                                      child: Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop();
                                                Navigator.push<void>(
                                                  context,
                                                  MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        CapturedPhotoDetailScreen(
                                                      capturedPhotoId: id,
                                                    ),
                                                  ),
                                                );
                                              },
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Colors.black.withValues(alpha: 0.55),
                                                foregroundColor: Colors.white,
                                              ),
                                              child: Text(
                                                widget.fil ? 'Buksan' : 'Open',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                child: Container(
                  width: 110,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: localPath == null
                        ? const Icon(Icons.image_not_supported)
                        : captureThumbnail(
                            localImagePath: localPath,
                            remoteImageUrl: remoteUrl,
                            images: _images,
                          ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// --- Diagnose tab: real stats from detections, line chart, My Fields ---
class _DiagnoseTab extends StatelessWidget {
  const _DiagnoseTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return const Center(child: Text('Sign in to see diagnose data'));
    }
    final DatabaseService localDb = DatabaseService();

    Future<DashboardStats> loadLocalStats() async {
      await localDb.initialize();
      final List<Map<String, dynamic>> rows =
          await localDb.getCapturedPhotos(limit: 500, userId: uid);
      return DashboardStatsCalculator.fromCapturedPhotos(rows);
    }

    Widget buildDiagnose(DashboardStats stats) {
      final String fieldsSubtitle = fil
          ? 'Mga imahe na nakuha sa ${stats.fieldCount} '
              '${stats.fieldCount == 1 ? 'field' : 'mga field'}'
          : 'Images captured in ${stats.fieldCount} '
              '${stats.fieldCount == 1 ? 'field' : 'fields'}';
      final String infestationSubtitle = fil
          ? 'ng iyong mga field na may mealybugs'
          : 'of your fields infested with mealybugs';

      return CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'DIAGNOSE',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const DiseaseInfoScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.search,
                              color: AppTheme.textMedium, size: 22),
                          SizedBox(width: 12),
                          Text(
                            'Search for Diseases',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                fil ? 'Ngayong Linggo' : 'This Week, You Have',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        color: AppTheme.primaryGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fil
                            ? 'Kabuuang images na nakuhanan ngayong linggo: ${stats.imageCount}'
                            : 'Overall images captured this week: ${stats.imageCount}',
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _StatCircle(
                      value: '${stats.imageCount}',
                      subtitle: fieldsSubtitle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCircle(
                      value: '${stats.infestationRate}%',
                      subtitle: infestationSubtitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                fil ? 'Kabuuang pests' : 'Total pests count',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _PestsChartFromData(
                fil: fil,
                dailyCounts: stats.dailyCounts,
                dates: stats.last7Days,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                fil ? 'Ang Aking mga Bukid' : 'My Fields',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _FieldsHorizontalList(uid: uid),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseClientProvider.instance.client
          .from('detections')
          .stream(primaryKey: const <String>['id'])
          .eq('user_id', uid),
      builder: (BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.hasError) {
          return FutureBuilder<DashboardStats>(
            future: loadLocalStats(),
            builder: (BuildContext context, AsyncSnapshot<DashboardStats> snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return buildDiagnose(snap.data!);
            },
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Map<String, dynamic>> docs = snapshot.data!;
        if (docs.isEmpty) {
          return FutureBuilder<DashboardStats>(
            future: loadLocalStats(),
            builder: (BuildContext context, AsyncSnapshot<DashboardStats> snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return buildDiagnose(snap.data!);
            },
          );
        }

        final DashboardStats stats =
            DashboardStatsCalculator.fromDetectionMaps(docs);
        return buildDiagnose(stats);
      },
    );
  }
}

class _StatCircle extends StatelessWidget {
  const _StatCircle({required this.value, required this.subtitle});

  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryGreen, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textDark,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PestsChartFromData extends StatelessWidget {
  const _PestsChartFromData({
    required this.fil,
    required this.dailyCounts,
    required this.dates,
  });

  final bool fil;
  final List<int> dailyCounts;
  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    final bool hasData = dailyCounts.any((int c) => c > 0);
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: hasData
          ? CustomPaint(
              painter: _RealLineChartPainter(
                dailyCounts: dailyCounts,
                dates: dates,
                fil: fil,
              ),
              size: Size.infinite,
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.show_chart,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fil ? 'Wala pang data' : 'No data yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fil ? 'Simulan ang scan para makita ang trends' : 'Start detecting to see trends',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RealLineChartPainter extends CustomPainter {
  _RealLineChartPainter({
    required this.dailyCounts,
    required this.dates,
    required this.fil,
  });

  final List<int> dailyCounts;
  final List<DateTime> dates;
  final bool fil;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0 || dailyCounts.isEmpty) return;

    final int maxY =
        dailyCounts.fold<int>(0, (int a, int b) => a > b ? a : b);
    final double rangeY = maxY > 0 ? maxY.toDouble() : 1.0;

    const double padLeft = 44;
    const double padRight = 10;
    const double padTop = 14;
    const double padBottom = 34;

    final double chartW = w - padLeft - padRight;
    final double chartH = h - padTop - padBottom;
    final double baseY = padTop + chartH;

    final int count = dailyCounts.length;
    final int pointCount = dates.length < count ? dates.length : count;
    if (pointCount < 2) return;

    final double xStep = chartW / (pointCount - 1);

    final List<Offset> points = <Offset>[];
    for (int i = 0; i < pointCount; i++) {
      final double x = padLeft + i * xStep;
      final double y =
          padTop + chartH - (dailyCounts[i].toDouble() / rangeY) * chartH;
      points.add(Offset(x, y));
    }

    // Grid + y labels
    const int yTicks = 4;
    for (int i = 0; i <= yTicks; i++) {
      final double t = i / yTicks;
      final double yValue = (rangeY * (1.0 - t));
      final double y = padTop + chartH - t * chartH;

      final Paint gridPaint = Paint()
        ..color = Colors.grey.shade200
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(padLeft, y),
        Offset(padLeft + chartW, y),
        gridPaint,
      );

      final String label = yValue == 0 ? '0' : yValue.round().toString();
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(padLeft - tp.width - 6, y - tp.height / 2));
    }

    // X labels
    String dayLabel(DateTime d) {
      // Monday=1 ... Sunday=7
      const List<String> en = <String>[
        '',
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun'
      ];
      const List<String> filLabels = <String>[
        '',
        'Lun',
        'Mar',
        'Miy',
        'Hul',
        'Biy',
        'Sab',
        'Lin'
      ];
      final int wday = d.weekday;
      return fil ? filLabels[wday] : en[wday];
    }

    for (int i = 0; i < pointCount; i++) {
      final DateTime d = dates[i];
      final String label = dayLabel(d);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double x = points[i].dx;
      tp.paint(canvas, Offset(x - tp.width / 2, baseY + 6));
    }

    // Find peak point to highlight (latest max)
    int peakIndex = 0;
    for (int i = 1; i < pointCount; i++) {
      if (dailyCounts[i] >= dailyCounts[peakIndex]) peakIndex = i;
    }
    final Offset peakPoint = points[peakIndex];

    // Vertical peak guide
    final Paint peakGuidePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(peakPoint.dx, padTop),
      Offset(peakPoint.dx, baseY),
      peakGuidePaint,
    );

    // Build a smooth path using Catmull-Rom -> Bezier conversion
    Path linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < pointCount - 1; i++) {
      final Offset p0 = points[i == 0 ? i : i - 1];
      final Offset p1 = points[i];
      final Offset p2 = points[i + 1];
      final Offset p3 =
          points[i + 2 < pointCount ? i + 2 : i + 1];

      // Tension = 1.0
      final Offset cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final Offset cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );

      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    // Area fill under the curve
    Path areaPath = Path()..moveTo(points[0].dx, baseY);
    areaPath.lineTo(points[0].dx, points[0].dy);
    for (int i = 0; i < pointCount - 1; i++) {
      final Offset p0 = points[i == 0 ? i : i - 1];
      final Offset p1 = points[i];
      final Offset p2 = points[i + 1];
      final Offset p3 =
          points[i + 2 < pointCount ? i + 2 : i + 1];

      final Offset cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final Offset cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );

      areaPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    areaPath.lineTo(points[pointCount - 1].dx, baseY);
    areaPath.close();

    final Paint areaPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: <Color>[
          AppTheme.primaryGreen.withValues(alpha: 0.18),
          AppTheme.primaryGreen.withValues(alpha: 0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(areaPath, areaPaint);

    // Glow + stroke
    final Paint glowPaint = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, glowPaint);

    final Paint strokePaint = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    // Dots for each day
    for (int i = 0; i < pointCount; i++) {
      final Offset p = points[i];
      final bool isPeak = i == peakIndex;
      if (isPeak) continue;

      final Paint outer = Paint()
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 5.5, outer);

      final Paint inner = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 3, inner);

      final Paint ring = Paint()
        ..color = AppTheme.primaryGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(p, 3.2, ring);
    }

    // Peak dot
    final Paint peakFill = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(peakPoint, 8, peakFill);
    final Paint peakRing = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(peakPoint, 8, peakRing);

    final TextPainter peakValuePainter = TextPainter(
      text: TextSpan(
        text: dailyCounts[peakIndex].toString(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    peakValuePainter.paint(
      canvas,
      Offset(peakPoint.dx - peakValuePainter.width / 2, peakPoint.dy - 7),
    );
  }

  @override
  bool shouldRepaint(covariant _RealLineChartPainter oldDelegate) =>
      oldDelegate.dailyCounts != dailyCounts ||
      oldDelegate.dates != dates ||
      oldDelegate.fil != fil;
}

// --- My Fields tab: tabs (My Fields | Reminders), grid + Add New Field ---
class _MyFieldsTab extends StatelessWidget {
  const _MyFieldsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: <Widget>[
                Text(
                  'MY FIELDS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                      width: 1.5),
                ),
                labelColor: AppTheme.textDark,
                unselectedLabelColor: AppTheme.textMedium,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                tabs: const <Tab>[
                  Tab(text: 'My Fields'),
                  Tab(text: 'Reminders'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Expanded(
            child: TabBarView(
              children: <Widget>[_MyFieldsGrid(), _RemindersPlaceholder()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyFieldsGrid extends StatelessWidget {
  const _MyFieldsGrid();

  @override
  Widget build(BuildContext context) {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: _EmptyFieldsMessage(),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseClientProvider.instance.client
          .from('fields')
          .stream(primaryKey: const <String>['id'])
          .eq('user_id', uid),
      builder: (BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Text('Error loading fields'));
        }
        final List<Map<String, dynamic>> docs = snapshot.data!;
        if (docs.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const _EmptyFieldsMessage(),
              const SizedBox(height: 16),
              _AddFieldCard(onTap: () => _openAddField(context)),
            ],
          );
        }
        final List<Map<String, dynamic>> fields = docs
            .map((Map<String, dynamic> data) {
          return <String, dynamic>{
            'fieldId': data['id'] as String,
            'name': data['name'] as String? ?? 'Field',
            'address': data['address'] as String? ?? '',
            'previewImagePath': data['preview_image_path'] as String?,
            'imageCount': (data['image_count'] as num?)?.toInt() ?? 0,
          };
        }).toList();
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: fields.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index == fields.length) {
              return _AddFieldCard(onTap: () => _openAddField(context));
            }
            return _FieldGridCard(
              field: fields[index],
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => FieldDetailScreen(
                      fieldId: fields[index]['fieldId'] as String,
                      fieldName: fields[index]['name'] as String,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static void _openAddField(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const FarmDetailsScreen()),
    );
  }
}

class _FieldGridCard extends StatelessWidget {
  const _FieldGridCard({required this.field, required this.onTap});

  final Map<String, dynamic> field;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: () {
                final String? previewPath = field['previewImagePath'] as String?;
                if (previewPath != null && previewPath.isNotEmpty) {
                  return Image.file(
                    File(previewPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.landscape,
                            size: 48, color: AppTheme.textMedium),
                      );
                    },
                  );
                }
                return Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.landscape,
                      size: 48, color: AppTheme.textMedium),
                );
              }(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    field['name'] as String,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((field['address'] as String).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Address: ${field['address']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMedium,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Photos captured: ${field['imageCount']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFieldCard extends StatelessWidget {
  const _AddFieldCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            BorderSide(color: AppTheme.primaryGreen.withValues(alpha: 0.6), width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.add, size: 48, color: AppTheme.primaryGreen),
              SizedBox(height: 8),
              Text(
                'Add New Field',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemindersPlaceholder extends StatelessWidget {
  const _RemindersPlaceholder();

  @override
  Widget build(BuildContext context) {
    final bool fil = context.watch<AppState>().isFilipino;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.notifications_none,
                size: 56, color: AppTheme.textMedium),
            const SizedBox(height: 16),
            const Text(
              'You Have No Reminders',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              fil
                  ? 'Dito lalabas ang mga paalala sa field checks, susunod na pagkuha ng larawan, at mga follow-up na dapat gawin.'
                  : 'This page shows reminders for field checks, next capture schedule, and pending follow-up surveys.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.textMedium),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const PhotoSourcePicker()),
                );
              },
              icon: const Icon(Icons.add_photo_alternate, size: 20),
              label: const Text('Add Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- More tab: profile card, General Info, Common Diseases, Explore by parts ---
class _MoreTab extends StatelessWidget {
  const _MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid =
        SupabaseClientProvider.instance.client.auth.currentUser?.id;
    return CustomScrollView(
      slivers: <Widget>[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: <Widget>[
                Text(
                  'MORE',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (uid == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _ProfileCard(
                username: 'User',
                email: '',
                photoUrl: null,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: SupabaseClientProvider.instance.client
                    .from('profiles')
                    .stream(primaryKey: const <String>['id'])
                    .eq('id', uid),
                builder: (BuildContext context,
                    AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                  final Map<String, dynamic>? data =
                      snapshot.data != null && snapshot.data!.isNotEmpty
                          ? snapshot.data!.first
                          : null;
                  final User? authUser =
                      SupabaseClientProvider.instance.client.auth.currentUser;
                  final String username = data?['display_name'] as String? ??
                      authUser?.phone ??
                      'User';
                  final String email = data?['email'] as String? ?? '';
                  final String? photoUrl = data?['photo_url'] as String?;
                  return _ProfileCard(
                    username: username,
                    email: email,
                    photoUrl: photoUrl,
                  );
                },
              ),
            ),
          ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'General Info',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: <Widget>[
                _InfoCard(
                  title: 'How to identify pineapples',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            EducationalContentScreen.identifyingPineapples()),
                  ),
                ),
                const SizedBox(width: 12),
                _InfoCard(
                  title: 'Difference between species of Pineapples',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            EducationalContentScreen.speciesDifferences()),
                  ),
                ),
                const SizedBox(width: 12),
                _InfoCard(
                  title: 'Why pineapples look different',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            EducationalContentScreen.whyDifferent()),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Common Diseases',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: <Widget>[
                _DiseaseCard(
                  title: 'Machete Disease',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseDetailScreen.machete()),
                  ),
                ),
                const SizedBox(width: 12),
                _DiseaseCard(
                  title: 'Heart Rot',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseDetailScreen.heartRot()),
                  ),
                ),
                const SizedBox(width: 12),
                _DiseaseCard(
                  title: 'Fusariosis',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseDetailScreen.fusariosis()),
                  ),
                ),
                const SizedBox(width: 12),
                _DiseaseCard(
                  title: 'Anthracnose',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseDetailScreen.anthracnose()),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Explore Diseases by parts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildListDelegate(
              <Widget>[
                _ExploreCard(
                  title: 'Disease of the whole Plant',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseByCategoryScreen.wholePlant()),
                  ),
                ),
                _ExploreCard(
                  title: 'Disease by Fruit',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseByCategoryScreen.fruit()),
                  ),
                ),
                _ExploreCard(
                  title: 'Disease caused by Pests',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseByCategoryScreen.pests()),
                  ),
                ),
                _ExploreCard(
                  title: 'Disease by Leaves',
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => DiseaseByCategoryScreen.leaves()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.username,
    required this.email,
    this.photoUrl,
  });

  final String username;
  final String email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppTheme.primaryGreen.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: CircleAvatar(
              radius: 35,
              backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                  ? NetworkImage(photoUrl!)
                  : null,
              backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
              child: photoUrl == null || photoUrl!.isEmpty
                  ? Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 28,
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    username,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings, color: AppTheme.primaryGreen),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.auto_stories,
                      color: AppTheme.primaryGreen, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.medical_services, color: AppTheme.primaryGreen, size: 28),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: Colors.grey.shade200,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.explore, color: AppTheme.primaryGreen, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared: horizontal field list and empty message ---
class _FieldsHorizontalList extends StatelessWidget {
  const _FieldsHorizontalList({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseClientProvider.instance.client
          .from('fields')
          .stream(primaryKey: const <String>['id'])
          .eq('user_id', uid),
      builder: (BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 140,
            child: Center(child: Text('Error loading fields')),
          );
        }
        final List<Map<String, dynamic>> docs = snapshot.data!;
        if (docs.isEmpty) {
          return const SizedBox(
            height: 140,
            child: Center(child: _EmptyFieldsMessage()),
          );
        }
        final List<Map<String, dynamic>> fields = docs
            .map((Map<String, dynamic> data) {
          return <String, dynamic>{
            'fieldId': data['id'] as String,
            'name': data['name'] as String? ?? 'Field',
            'address': data['address'] as String? ?? '',
            'imageCount': (data['image_count'] as num?)?.toInt() ?? 0,
          };
        }).toList();
        return SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: fields.length,
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> field = fields[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _FieldHorizontalCard(
                  field: field,
                  onTap: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => FieldDetailScreen(
                          fieldId: field['fieldId'] as String,
                          fieldName: field['name'] as String,
                        ),
                      ),
                    );
                  },
                  onEdit: () {
                    final String? fieldId = field['fieldId'] as String?;
                    if (fieldId == null) return;
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => EditFieldScreen(fieldId: fieldId),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FieldHorizontalCard extends StatelessWidget {
  const _FieldHorizontalCard({
    required this.field,
    required this.onTap,
    required this.onEdit,
  });

  final Map<String, dynamic> field;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.landscape,
                            size: 40, color: AppTheme.textMedium),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            field['name'] as String,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((field['address'] as String).isNotEmpty)
                            Text(
                              field['address'] as String,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMedium,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            'Photos: ${field['imageCount']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit field',
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.primaryGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFieldsMessage extends StatelessWidget {
  const _EmptyFieldsMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.landscape_outlined,
                size: 48, color: AppTheme.textMedium),
            SizedBox(height: 12),
            Text(
              'No fields yet',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Add a field from My Fields or open map to pin a location.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMedium),
            ),
          ],
        ),
      ),
    );
  }
}
