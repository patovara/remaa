import 'package:flutter_test/flutter_test.dart';
import 'package:rema_app/features/catalogo/domain/catalog_csv_parser.dart';

void main() {
  test('parseCatalogCsv valida encabezados y convierte filas validas', () {
    const csv = '''universe,concept,unit,base_price,attribute,option
Recubrimientos,Pintura vinilica,m2,120,Marca,Comex
Recubrimientos,Pintura vinilica,m2,120,Marca,Berel
Recubrimientos,Pintura vinilica,m2,120,Acabado,Mate
''';

    final result = parseCatalogCsv(csv);

    expect(result.issues, isEmpty);
    expect(result.rows, hasLength(3));
    expect(result.rows.first.universe, 'Recubrimientos');
    expect(result.rows.first.basePrice, 120);
    expect(result.rows.last.attribute, 'Acabado');
  });

  test('parseCatalogCsv reporta columnas faltantes', () {
    const csv = 'universe,concept\nRecubrimientos,Pintura';

    final result = parseCatalogCsv(csv);

    expect(result.rows, isEmpty);
    expect(result.issues, isNotEmpty);
  });
}