#!/bin/sh

dart -v ./unpub/bin/unpub.dart -d ${DB_URL} --proxy-origin ${HOST_NAME} --roleArn ${AWS_ROLE_ARN} --roleSessionName 'unpubS3Store' --region ${AWS_REGION} --webIdentityTokenFile ${AWS_WEB_IDENTITY_TOKEN_FILE} --bucketName ${AWS_BUCKET_NAME} -e true