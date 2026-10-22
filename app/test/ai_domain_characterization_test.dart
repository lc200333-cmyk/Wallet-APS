import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/controllers/entity_index.dart';
import 'package:wallet_aps/domain/card_layout.dart';
import 'package:wallet_aps/features/cards/field_projection.dart';
import 'package:wallet_aps/features/categories/category_path_index.dart';
import 'package:wallet_aps/features/templates/template_order.dart';

void main() {
  test('duplicate entity IDs retain the last entity', () {
    expect(indexEntitiesById(['first', 'last'], (_) => 'id'), {'id': 'last'});
    expect(indexEntitiesById<String>([], (value) => value), isEmpty);
  });

  test('category paths trim names and terminate for orphans and cycles', () {
    final categories = [
      (id: 'root', parent: '', name: ' Root '),
      (id: 'blank', parent: 'root', name: '  '),
      (id: 'leaf', parent: 'blank', name: ' Leaf '),
      (id: 'orphan', parent: 'missing', name: 'Orphan'),
      (id: 'a', parent: 'b', name: 'A'),
      (id: 'b', parent: 'a', name: 'B'),
      (id: 'self', parent: 'self', name: 'Self'),
    ];
    expect(
      buildCategoryPathsById(
        categories,
        idOf: (c) => c.id,
        parentIdOf: (c) => c.parent,
        nameOf: (c) => c.name,
      ),
      {
        'root': 'Root',
        'blank': 'Root',
        'leaf': 'Root / Leaf',
        'orphan': 'Orphan',
        'a': 'B / A',
        'b': 'A / B',
        'self': 'Self',
      },
    );
  });

  test('projection preserves orphan values and ignores hidden or unknown IDs',
      () {
    expect(
      projectVisibleFieldIds(
        definedIds: ['a', 'b', 'hidden', 'a'],
        valueIds: ['orphan', 'b', 'tail'],
        preferredOrder: ['missing', 'orphan', 'hidden', 'orphan'],
        hiddenIds: {'hidden'},
      ),
      ['orphan', 'a', 'b', 'tail'],
    );
  });

  test('layout serialization is deterministic and retains modification time',
      () {
    final previous = CardLayoutState(
      fieldOrder: ['b', 'a'],
      hiddenFieldIds: {'z', 'a'},
      modifiedAt: DateTime.utc(2026, 1, 2),
    );
    expect(previous.encodeLayout(), '{"order":["b","a"],"hidden":["a","z"]}');
    final restored =
        CardLayoutState.decodeLayout(previous.encodeLayout(), previous);
    expect(restored.fieldOrder, ['b', 'a']);
    expect(restored.hiddenFieldIds, {'a', 'z'});
    expect(restored.modifiedAt, previous.modifiedAt);
    for (final malformed in ['broken', '[]', '{"order":[1]}']) {
      expect(CardLayoutState.decodeLayout(malformed, previous), same(previous));
    }
  });

  test('case insensitive template ordering uses ID to break ties', () {
    expect(compareNamedEntities('alpha', '2', 'ALPHA', '1'), greaterThan(0));
    expect(compareNamedEntities('alpha', '9', 'Beta', '1'), lessThan(0));
    expect(compareNamedEntities('A', '1', 'a', '1'), 0);
  });
}
