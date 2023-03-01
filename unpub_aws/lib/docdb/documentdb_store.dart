import 'package:aws_docdb_api/docdb-2014-10-31.dart';
import 'package:unpub/unpub.dart';

class DocumentDbStore extends MetaStore {
  Function(String)? onDatabaseError;

  DocumentDbStore(this.db, {this.onDatabaseError});

  final service = DocDB(region: 'eu-west-1');

  @override
  Future<void> addUploader(String name, String email) {
    servie
  }

  @override
  Future<void> addVersion(String name, UnpubVersion version) {
    // TODO: implement addVersion
    throw UnimplementedError();
  }

  @override
  void increaseDownloads(String name, String version) {
    // TODO: implement increaseDownloads
  }

  @override
  Future<UnpubPackage?> queryPackage(String name) {
    // TODO: implement queryPackage
    throw UnimplementedError();
  }

  @override
  Future<UnpubQueryResult> queryPackages(
      {required int size,
      required int page,
      required String sort,
      String? keyword,
      String? uploader,
      String? dependency}) {
    // TODO: implement queryPackages
    throw UnimplementedError();
  }

  @override
  Future<void> removeUploader(String name, String email) {
    // TODO: implement removeUploader
    throw UnimplementedError();
  }
}
