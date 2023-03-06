#!/bin/sh

dart ./unpub/bin/unpub.dart -d ${DB_URL} --proxy-origin ${HOST_NAME} --dynamoDbUrl "https://dynamodb.eu-west-1.amazonaws.com" --dynamoDbTableName unpub-test -e true
