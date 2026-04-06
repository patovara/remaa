import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum ImageOptimizationProfile { mainDocument, gridDocument }

class OptimizedImageResult {
  const OptimizedImageResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.widthPx,
    required this.heightPx,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int widthPx;
  final int heightPx;
}

class ImageOptimizationException implements Exception {
  const ImageOptimizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

const int maxImageInputBytes = 10 * 1024 * 1024;
const int targetImageMaxBytes = 300 * 1024;
const int clientLogoMaxSidePx = 500;
const int targetClientLogoMaxBytes = 180 * 1024;

Future<OptimizedImageResult> optimizeImageForDocument({
  required Uint8List inputBytes,
  required String fileName,
  required ImageOptimizationProfile profile,
}) async {
  if (inputBytes.isEmpty) {
    throw const ImageOptimizationException('La imagen seleccionada esta vacia.');
  }
  if (inputBytes.length > maxImageInputBytes) {
    throw const ImageOptimizationException(
      'La imagen excede el maximo permitido de 10 MB antes de procesarla.',
    );
  }

  final result = await compute(
    _optimizeImagePayload,
    <String, Object>{
      'bytes': inputBytes,
      'fileName': fileName,
      'maxWidth': profile == ImageOptimizationProfile.gridDocument ? 800 : 1280,
    },
  );

  if (result['ok'] != true) {
    final message = result['message'] as String? ?? 'No se pudo optimizar la imagen.';
    throw ImageOptimizationException(message);
  }

  return OptimizedImageResult(
    bytes: result['bytes'] as Uint8List,
    fileName: result['fileName'] as String,
    mimeType: result['mimeType'] as String,
    widthPx: result['widthPx'] as int,
    heightPx: result['heightPx'] as int,
  );
}

Future<OptimizedImageResult> optimizeImageForClientLogo({
  required Uint8List inputBytes,
  required String fileName,
}) async {
  if (inputBytes.isEmpty) {
    throw const ImageOptimizationException('La imagen seleccionada esta vacia.');
  }
  if (inputBytes.length > maxImageInputBytes) {
    throw const ImageOptimizationException(
      'La imagen excede el maximo permitido de 10 MB antes de procesarla.',
    );
  }

  final result = await compute(
    _optimizeClientLogoPayload,
    <String, Object>{
      'bytes': inputBytes,
      'fileName': fileName,
    },
  );

  if (result['ok'] != true) {
    final message = result['message'] as String? ?? 'No se pudo optimizar el logo.';
    throw ImageOptimizationException(message);
  }

  return OptimizedImageResult(
    bytes: result['bytes'] as Uint8List,
    fileName: result['fileName'] as String,
    mimeType: result['mimeType'] as String,
    widthPx: result['widthPx'] as int,
    heightPx: result['heightPx'] as int,
  );
}

Map<String, Object> _optimizeImagePayload(Map<String, Object> payload) {
  final inputBytes = payload['bytes'] as Uint8List;
  final fileName = payload['fileName'] as String;
  final maxWidth = payload['maxWidth'] as int;

  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    return <String, Object>{
      'ok': false,
      'message': 'No se pudo decodificar la imagen seleccionada.',
    };
  }

  final baked = img.bakeOrientation(decoded);
  final widthCandidates = _buildWidthCandidates(baked.width, maxWidth);
  const qualityCandidates = <int>[80, 76, 72, 68];

  Uint8List? bestBytes;
  int? bestWidth;
  int? bestHeight;

  for (final width in widthCandidates) {
    final resized = width == baked.width
        ? baked.clone()
        : img.copyResize(
            baked,
            width: width,
            interpolation: img.Interpolation.average,
          );

    for (final quality in qualityCandidates) {
      final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (bestBytes == null || encoded.length < bestBytes.length) {
        bestBytes = encoded;
        bestWidth = resized.width;
        bestHeight = resized.height;
      }
      if (encoded.length <= targetImageMaxBytes) {
        return <String, Object>{
          'ok': true,
          'bytes': encoded,
          'fileName': _normalizedJpgName(fileName),
          'mimeType': 'image/jpeg',
          'widthPx': resized.width,
          'heightPx': resized.height,
        };
      }
    }
  }

  if (bestBytes == null || bestWidth == null || bestHeight == null) {
    return <String, Object>{
      'ok': false,
      'message': 'No se pudo generar una version optimizada de la imagen.',
    };
  }

  return <String, Object>{
    'ok': true,
    'bytes': bestBytes,
    'fileName': _normalizedJpgName(fileName),
    'mimeType': 'image/jpeg',
    'widthPx': bestWidth,
    'heightPx': bestHeight,
  };
}

Map<String, Object> _optimizeClientLogoPayload(Map<String, Object> payload) {
  final inputBytes = payload['bytes'] as Uint8List;
  final fileName = payload['fileName'] as String;

  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    return <String, Object>{
      'ok': false,
      'message': 'No se pudo decodificar la imagen seleccionada.',
    };
  }

  final baked = img.bakeOrientation(decoded);
  final squareSide = baked.width < baked.height ? baked.width : baked.height;
  final cropX = (baked.width - squareSide) ~/ 2;
  final cropY = (baked.height - squareSide) ~/ 2;
  final cropped = img.copyCrop(
    baked,
    x: cropX,
    y: cropY,
    width: squareSide,
    height: squareSide,
  );
  final targetSide = squareSide > clientLogoMaxSidePx ? clientLogoMaxSidePx : squareSide;
  final resized = targetSide == cropped.width
      ? cropped
      : img.copyResize(
          cropped,
          width: targetSide,
          height: targetSide,
          interpolation: img.Interpolation.average,
        );

  const qualityCandidates = <int>[82, 78, 74, 70, 66];
  Uint8List? bestBytes;

  for (final quality in qualityCandidates) {
    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (bestBytes == null || encoded.length < bestBytes.length) {
      bestBytes = encoded;
    }
    if (encoded.length <= targetClientLogoMaxBytes) {
      return <String, Object>{
        'ok': true,
        'bytes': encoded,
        'fileName': _normalizedJpgName(fileName),
        'mimeType': 'image/jpeg',
        'widthPx': resized.width,
        'heightPx': resized.height,
      };
    }
  }

  if (bestBytes == null) {
    return <String, Object>{
      'ok': false,
      'message': 'No se pudo generar una version optimizada del logo.',
    };
  }

  return <String, Object>{
    'ok': true,
    'bytes': bestBytes,
    'fileName': _normalizedJpgName(fileName),
    'mimeType': 'image/jpeg',
    'widthPx': resized.width,
    'heightPx': resized.height,
  };
}

List<int> _buildWidthCandidates(int originalWidth, int maxWidth) {
  final startWidth = originalWidth > maxWidth ? maxWidth : originalWidth;
  final widths = <int>{startWidth};
  if (startWidth > 1120) {
    widths.add(1120);
  }
  if (startWidth > 960) {
    widths.add(960);
  }
  if (startWidth > 800) {
    widths.add(800);
  }
  if (startWidth > 720) {
    widths.add(720);
  }
  if (startWidth > 640) {
    widths.add(640);
  }
  final sorted = widths.toList()..sort((a, b) => b.compareTo(a));
  return sorted;
}

String _normalizedJpgName(String fileName) {
  final normalized = fileName.trim();
  if (normalized.isEmpty) {
    return 'imagen_opt.jpg';
  }
  final dot = normalized.lastIndexOf('.');
  final baseName = dot <= 0 ? normalized : normalized.substring(0, dot);
  return '$baseName.jpg';
}