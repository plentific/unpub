import 'package:aws_dynamodb_api/dynamodb-2012-08-10.dart';
import 'package:unpub/unpub.dart';

class DynamoDBMetaStore extends MetaStore {
  DynamoDBMetaStore({
    required String endpointUrl,
    this.tableName,
  }) : client = DynamoDB(
          region: 'eu-west-1',
          endpointUrl: endpointUrl,
        );

  final tableName;

  final DynamoDB client;
  @override
  Future<void> addVersion(String name, UnpubVersion version) async {
    await _createTable();

    await client.updateItem(
      key: {
        'name': AttributeValue(s: '1'),
      },
      attributeUpdates: {
        'versions': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(
            m: version.toJson().map(
                  (key, value) => MapEntry(
                    key,
                    AttributeValue(s: value.toString()),
                  ),
                ),
          ),
        ),
        'uploaders': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(s: version.uploader),
        ),
        'createdAt': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(s: version.createdAt.toIso8601String()),
        ),
        'private': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(boolValue: true),
        ),
        'download': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(n: '0'),
        ),
        'updatedAt': AttributeValueUpdate(
          action: AttributeAction.put,
          value: AttributeValue(s: version.createdAt.toIso8601String()),
        ),
      },
      tableName: tableName,
    );
  }

  Future<void> _createTable() async {
    final attributeDefinitions = <AttributeDefinition>[
      AttributeDefinition(
        attributeName: "name",
        attributeType: ScalarAttributeType.s,
      ),
    ];

    final keySchema = <KeySchemaElement>[
      KeySchemaElement(
        attributeName: "name",
        keyType: KeyType.hash,
      ),
    ];

    await client.createTable(
      attributeDefinitions: attributeDefinitions,
      keySchema: keySchema,
      tableName: tableName,
      provisionedThroughput: ProvisionedThroughput(readCapacityUnits: 20, writeCapacityUnits: 20),
    );
  }

  @override
  Future<void> addUploader(String name, String email) async {
    ;
  }

  @override
  void increaseDownloads(String name, String version) async {
    ;
  }

  @override
  Future<UnpubPackage?> queryPackage(String name) async {
    return null;
  }

  @override
  Future<UnpubQueryResult> queryPackages(
      {required int size,
      required int page,
      required String sort,
      String? keyword,
      String? uploader,
      String? dependency}) async {
    final x = await client.scan(
      tableName: tableName,
    );
    print(x.items.toString());
    return UnpubQueryResult(0, []);
  }

  @override
  Future<void> removeUploader(String name, String email) async {
    return;
  }
}
