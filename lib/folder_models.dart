class FavoriteFolder {
  final String uri, name;
  const FavoriteFolder({required this.uri, required this.name});
  factory FavoriteFolder.fromJson(Map<String, dynamic> json) =>
      FavoriteFolder(uri: json['uri'] as String, name: json['name'] as String);
  Map<String, dynamic> toJson() => {'uri': uri, 'name': name};
}

class FolderEntry {
  final String uri, name, path;
  final bool isDirectory, canDelete, supportsDelete;
  final int modified;
  const FolderEntry({
    required this.uri,
    required this.name,
    required this.path,
    required this.isDirectory,
    this.modified = 0,
    this.canDelete = false,
    this.supportsDelete = false,
  });
  factory FolderEntry.fromJson(Map<String, dynamic> json) => FolderEntry(
    uri: json['uri'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    isDirectory: json['isDirectory'] as bool,
    modified: (json['modified'] as num?)?.toInt() ?? 0,
    canDelete: json['canDelete'] as bool? ?? false,
    supportsDelete:
        json['supportsDelete'] as bool? ?? json['canDelete'] as bool? ?? false,
  );
}

class FolderListing {
  final List<FolderEntry> entries;
  final bool truncated;
  const FolderListing(this.entries, {this.truncated = false});
  factory FolderListing.fromJson(Map<String, dynamic> json) => FolderListing(
    (json['entries'] as List)
        .map(
          (entry) =>
              FolderEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(),
    truncated: json['truncated'] as bool? ?? false,
  );
}
