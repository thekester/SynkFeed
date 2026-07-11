class RetentionPolicy {
  const RetentionPolicy({
    this.retentionDays = 30,
    this.maximumArticlesPerFeed,
    this.maximumCacheBytes = 500 * 1024 * 1024,
    this.downloadImages = true,
    this.imagesOnWifiOnly = true,
    this.preserveUnread = true,
    this.preserveStarred = true,
  }) : assert(retentionDays == null || retentionDays > 0),
       assert(maximumArticlesPerFeed == null || maximumArticlesPerFeed > 0),
       assert(maximumCacheBytes > 0);

  final int? retentionDays;
  final int? maximumArticlesPerFeed;
  final int maximumCacheBytes;
  final bool downloadImages;
  final bool imagesOnWifiOnly;
  final bool preserveUnread;
  final bool preserveStarred;

  RetentionPolicy copyWith({
    Object? retentionDays = _unset,
    Object? maximumArticlesPerFeed = _unset,
    int? maximumCacheBytes,
    bool? downloadImages,
    bool? imagesOnWifiOnly,
    bool? preserveUnread,
    bool? preserveStarred,
  }) => RetentionPolicy(
    retentionDays: identical(retentionDays, _unset)
        ? this.retentionDays
        : retentionDays as int?,
    maximumArticlesPerFeed: identical(maximumArticlesPerFeed, _unset)
        ? this.maximumArticlesPerFeed
        : maximumArticlesPerFeed as int?,
    maximumCacheBytes: maximumCacheBytes ?? this.maximumCacheBytes,
    downloadImages: downloadImages ?? this.downloadImages,
    imagesOnWifiOnly: imagesOnWifiOnly ?? this.imagesOnWifiOnly,
    preserveUnread: preserveUnread ?? this.preserveUnread,
    preserveStarred: preserveStarred ?? this.preserveStarred,
  );
}

const Object _unset = Object();
