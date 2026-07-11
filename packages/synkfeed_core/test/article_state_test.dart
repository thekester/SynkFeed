import 'package:synkfeed_core/synkfeed_core.dart';
import 'package:test/test.dart';

void main() {
  test('article state transitions update logical version', () {
    final base = ArticleState(
      userId: 'user-1',
      articleId: 'article-1',
      isRead: false,
      readAt: null,
      isStarred: false,
      starredAt: null,
      isArchived: false,
      updatedAt: DateTime.utc(2026, 7, 11, 12, 0, 0),
      logicalVersion: 7,
    );

    final read = base.markRead(true, at: DateTime.utc(2026, 7, 11, 12, 1, 0));
    expect(read.isRead, isTrue);
    expect(read.readAt, DateTime.utc(2026, 7, 11, 12, 1, 0));
    expect(read.logicalVersion, 8);

    final starred = read.markStarred(
      true,
      at: DateTime.utc(2026, 7, 11, 12, 2, 0),
    );
    expect(starred.isStarred, isTrue);
    expect(starred.starredAt, DateTime.utc(2026, 7, 11, 12, 2, 0));
    expect(starred.logicalVersion, 9);

    final cleared = starred
        .markRead(false, at: DateTime.utc(2026, 7, 11, 12, 3))
        .markStarred(false, at: DateTime.utc(2026, 7, 11, 12, 4));
    expect(cleared.readAt, isNull);
    expect(cleared.starredAt, isNull);
  });
}
