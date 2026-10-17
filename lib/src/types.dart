typedef FileMetadata = ({
  String extension,
  String language,
  int size,
  int mtime,
  int loc,
  String classification,
  String directory,
  int depth,
});

extension FileMetadataToMap
    on
        ({
          String extension,
          String language,
          int size,
          int mtime,
          int loc,
          String classification,
          String directory,
          int depth,
        }) {
  Map<String, dynamic> toMap() {
    return {
      'extension': extension,
      'language': language,
      'size': size,
      'mtime': mtime,
      'loc': loc,
      'classification': classification,
      'directory': directory,
      'depth': depth,
    };
  }
}
