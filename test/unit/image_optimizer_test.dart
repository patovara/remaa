import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rema_app/core/utils/image_optimizer.dart';

void main() {
  test('optimizeImageForClientLogo recorta al centro y limita a 500x500', () async {
    final source = img.Image(width: 1200, height: 800);
    final sourceBytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));

    final optimized = await optimizeImageForClientLogo(
      inputBytes: sourceBytes,
      fileName: 'logo_original.png',
    );

    final decoded = img.decodeImage(optimized.bytes);

    expect(optimized.mimeType, 'image/jpeg');
    expect(optimized.fileName, 'logo_original.jpg');
    expect(optimized.widthPx, 500);
    expect(optimized.heightPx, 500);
    expect(decoded, isNotNull);
    expect(decoded!.width, 500);
    expect(decoded.height, 500);
  });
}