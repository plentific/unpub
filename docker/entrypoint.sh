#!/bin/sh

dart ./unpub/bin/unpub.dart -d ${DB_URL} --proxy-origin ${HOST_NAME} -e true --roleArn ${AWS_ROLE_ARN} --roleSessionName 'unpubS3Store' --webIdentityTokenFile ${AWS_WEB_IDENTITY_TOKEN} --bucketName ${AWS_BUCKET_NAME}