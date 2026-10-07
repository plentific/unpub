# Unpub

[![pub](https://img.shields.io/pub/v/unpub.svg)](https://pub.dev/packages/unpub)

Unpub is a self-hosted private Dart Pub server for Enterprise, with a simple web interface to search and view packages information.

## This fork

This is Plentific's fork. Its server, `unpub/bin/unpub.dart`, keeps package metadata in a MongoDB compatible database (Amazon DocumentDB in production) and package archives in S3 through `unpub_aws`, with credentials from STS (IAM roles for service accounts on EKS). A package it does not have is answered with 404, not sent on to pub.dev.

### Configuration

The image's entrypoint passes these environment variables on:

| Variable | Option | |
| --- | --- | --- |
| `DB_URL` | `--database` | MongoDB URI; `authMechanism` defaults to SCRAM-SHA-1, the one DocumentDB supports |
| `CA_PATH` | `--tlsCAFile` | CA bundle for TLS to the database; empty for an unencrypted connection |
| `HOST_NAME` | `--proxy-origin` | Public origin of the server, used in the archive URLs given to `dart pub` |

The server also reads `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` (or `AWS_WEB_IDENTITY_TOKEN`), `AWS_REGION` (default `eu-west-1`) and `AWS_BUCKET_NAME`. EKS sets the first three for a pod with an IAM role; the bucket comes from the deployment. A missing setting stops the server at startup, before it connects to anything.

### Deployment

The Jenkinsfile builds `docker/Dockerfile` for every branch. On `master` it also writes the new image tag to plentific/devops-cd and syncs the ArgoCD application `unpub`, so merging to `master` deploys.

### Logs

The server logs to standard output, which is the pod's log (ArgoCD shows it too). Lines worth knowing:

- `Connecting to database using …` then `Serving at http://0.0.0.0:4000`: a normal start.
- `Database connection lost, reconnecting` and `Database reconnected`: the database closed the connection (a failover, maintenance). Requests during the reconnect fail; the next ones succeed.
- `Refreshing AWS credentials failed, retrying in 30s: …`: STS refused a refresh. Uploads and downloads keep using the current credentials until they expire.
- `Could not create the database indexes, serving without them: …`: usually two documents with the same package name.
- `SIGTERM received, closing the server`: Kubernetes is stopping the pod.

### Web pages

The server renders its web pages itself (`unpub/lib/src/web/`), in Plentific's look: the Plentific logo, and the colours and Figtree font of the Plentific dashboard's design tokens, light and dark. The pages run no JavaScript, so there is nothing to build: readmes and changelogs are sanitized, and their Content-Security-Policy lets a page load only its own styles, Figtree from Google Fonts and https images.

### Development

- `dart test` in `unpub` runs every test. The ones tagged `mongodb` need MongoDB on localhost:27017 (`docker compose -f unpub_aws/docker-compose.yml up mongo`); `dart test --exclude-tags mongodb` leaves them out.
- Generated code: `dart run build_runner build --delete-conflicting-outputs` in `unpub`.
- Formatting: 120 columns, set in each package's `analysis_options.yaml`; generated `*.g.dart` files keep their generators' format.

## Screenshots

![A package page](https://raw.githubusercontent.com/plentific/unpub/master/assets/screenshot.png)

## Usage

### Command Line

```sh
pub global activate unpub
unpub --database mongodb://localhost:27017/dart_pub # Replace this with production database uri
```

Unpub use mongodb as meta information store and file system as package(tarball) store by default.

Dart API is also available for further customization.

### Dart API

```dart
import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/unpub.dart' as unpub;

main(List<String> args) async {
  final db = Db('mongodb://localhost:27017/dart_pub');
  await db.open(); // make sure the MongoDB connection opened

  final app = unpub.App(
    metaStore: unpub.MongoStore(db),
    packageStore: unpub.FileStore('./unpub-packages'),
  );

  final server = await app.serve('0.0.0.0', 4000);
  print('Serving at http://${server.address.host}:${server.port}');
}
```

### Options

| Option | Description | Default |
| --- | --- | --- |
| `metaStore` (Required) | Meta information store | - |
| `packageStore` (Required) | Package(tarball) store | - |
| `upstream` | Upstream url | https://pub.dev |
| `googleapisProxy` | Http(s) proxy to call googleapis (to get uploader email) | - |
| `uploadValidator` | See [Package validator](#package-validator) | - |


### Usage behind reverse-proxy

Using unpub behind reverse proxy(nginx or another), ensure you have necessary headers
```sh
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Server $host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

# Workaround for: 
# Asynchronous error HttpException: 
# Trying to set 'Transfer-Encoding: Chunked' on HTTP 1.0 headers
proxy_http_version 1.1;
```

### Package validator

Naming conflicts is a common issue for private registry. A reasonable solution is to add prefix to reduce conflict probability.

With `uploadValidator` you could check if uploaded package is valid.

```dart
var app = unpub.App(
  // ...
  uploadValidator: (Map<String, dynamic> pubspec, String uploaderEmail) {
    // Only allow packages with some specified prefixes to be uploaded
    var prefix = 'my_awesome_prefix_';
    var name = pubspec['name'] as String;
    if (!name.startsWith(prefix)) {
      throw 'Package name should starts with $prefix';
    }

    // Also, you can check if uploader email is valid
    if (!uploaderEmail.endsWith('@your-company.com')) {
      throw 'Uploader email invalid';
    }
  }
);
```

### Customize meta and package store

Unpub is designed to be extensible. It is quite easy to customize your own meta store and package store.

```dart
import 'package:unpub/unpub.dart' as unpub;

class MyAwesomeMetaStore extends unpub.MetaStore {
  // Implement methods of MetaStore abstract class
  // ...
}

class MyAwesomePackageStore extends unpub.PackageStore {
  // Implement methods of PackageStore abstract class
  // ...
}

// Then use it
var app = unpub.App(
  metaStore: MyAwesomeMetaStore(),
  packageStore: MyAwesomePackageStore(),
);
```

#### Available Package Stores

1. [unpub_aws](https://github.com/bytedance/unpub/tree/master/unpub_aws): AWS S3 package store, maintained by [@CleanCode](https://github.com/Clean-Cole).

## Badges

| URL | Badge |
| --- | --- |
| `/badge/v/{package_name}` | ![badge example](https://img.shields.io/static/v1?label=unpub&message=0.1.0&color=orange) ![badge example](https://img.shields.io/static/v1?label=unpub&message=1.0.0&color=blue) |
| `/badge/d/{package_name}` | ![badge example](https://img.shields.io/static/v1?label=downloads&message=123&color=blue) |

## Alternatives

- [pub-dev](https://github.com/dart-lang/pub-dev): Source code of [pub.dev](https://pub.dev), which should be deployed at Google Cloud Platform.
- [pub_server](https://github.com/dart-lang/pub_server): An alpha version of pub server provided by Dart team.

## Credits

- [shields](https://shields.io): Badges generation.

## License

MIT
