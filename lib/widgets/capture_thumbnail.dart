library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../services/image_storage_service.dart';

/// Shows a capture thumbnail from local disk when available, otherwise from
/// [remoteImageUrl] (Supabase public URL).
Widget captureThumbnail({
  required String localImagePath,
  String? remoteImageUrl,
  required ImageStorageService images,
  BoxFit fit = BoxFit.cover,
}) {
  return FutureBuilder<File?>(
    future: localImagePath == DatabaseService.remoteOnlyLocalPath
        ? Future<File?>.value(null)
        : images.getImageFile(localImagePath),
    builder: (BuildContext context, AsyncSnapshot<File?> snap) {
      final File? file = snap.data;
      if (file != null) {
        return Image.file(file, fit: fit);
      }
      final String? url = remoteImageUrl?.trim();
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          fit: fit,
          errorBuilder: (
            BuildContext _,
            Object __,
            StackTrace? ___,
          ) {
            return Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.image_outlined),
            );
          },
          loadingBuilder: (
            BuildContext _,
            Widget child,
            ImageChunkEvent? loadingProgress,
          ) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        );
      }
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_outlined),
      );
    },
  );
}
