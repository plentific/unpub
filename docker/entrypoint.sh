#!/bin/sh

dart ./unpub/bin/unpub.dart -d ${DB_URL} --proxy-origin ${HOST_NAME} -e true -s3bucket 'bucket' -s3accessKey 'access' -s3secretKey 'secret' -s3region 'region'