# unpub_aws

Modules to deploy unpub on AWS.

## S3 package store with IAM roles for service accounts

`S3StoreIamStore` keeps package archives in an S3 bucket, as `<name>-<version>.tar.gz` (with `+` replaced by `.`).
It signs S3 requests with temporary credentials from STS `AssumeRoleWithWebIdentity`, so on EKS it works with
[IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
and needs no static access keys.

The server in `unpub/bin/unpub.dart` sets it up from these options, which default to the environment variables that
EKS injects into the pod:

| Option | Environment variable | |
| --- | --- | --- |
| `--roleArn` | `AWS_ROLE_ARN` | Role to assume |
| `--webIdentityTokenFile` | `AWS_WEB_IDENTITY_TOKEN_FILE` | Projected service account token |
| `--webIdentityToken` | `AWS_WEB_IDENTITY_TOKEN` | A token given as a value instead of a file |
| `--roleSessionName` | | Defaults to `unpubConnection` |
| `--bucketName` | `AWS_BUCKET_NAME` | Bucket for the package archives |
| `--region` | `AWS_REGION` | Defaults to `eu-west-1` |
