#!/usr/bin/env bash

function get_from_parameter_store {
    aws ssm get-parameters --names $1 --with-decryption --output text | awk '{print $4}'
}

export AWS_DEFAULT_REGION="us-west-2"
export AWS_SECRET_ACCESS_KEY=`get_from_parameter_store "SECRET_ACCESS_KEY"`
export AWS_ACCESS_KEY_ID=`get_from_parameter_store "ACCESS_KEY_ID"`

export DB_NAME=`get_from_parameter_store "DB_NAME"`
export DB_USER=`get_from_parameter_store "DB_USER"`
export DB_PASS=`get_from_parameter_store "DB_PASS"`
export LOGIN_HOST="localhost"
TEST_DB_INSTANCE_ID="demo1-test"
DB_INSTANCE_ID="demo2"

APP_PROPERTIES="${WORKSPACE}/src/main/resources/application.properties"
APP_PROPERTIES_TEMPLATE="${APP_PROPERTIES}.template"

# Obtain RDS database endpoint
echo "Obtaining RDS database endpoint ..."
EXISTING_DB_INSTANCE_INFO=""
MAX_RETRIES_TO_GET_DBINFO=20
RETRIES=0
while [[ -z `echo ${EXISTING_DB_INSTANCE_INFO} | grep "amazonaws"` ]] && [ ${RETRIES} -lt ${MAX_RETRIES_TO_GET_DBINFO} ]; do
    sleep 20
    EXISTING_DB_INSTANCE_INFO=`aws rds describe-db-instances --db-instance-identifier ${DB_INSTANCE_ID} \
    --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output text`
    echo "Try: ${RETRIES}    DBinfo: ${EXISTING_DB_INSTANCE_INFO}"
    let "RETRIES++"
done
if [[ -z `echo ${EXISTING_DB_INSTANCE_INFO} | grep "amazonaws"` ]]; then
    echo "Failure - no RDS database with identifier ${DB_INSTANCE_ID} available."
    exit 1
fi
export DB_HOST=`echo ${EXISTING_DB_INSTANCE_INFO} | awk '{print $2}'`
export DB_PORT=`echo ${EXISTING_DB_INSTANCE_INFO} | awk '{print $3}'`
echo "RDS endpoint: ${DB_HOST}:${DB_PORT}  Retries: ${RETRIES}"

# Insert database parameters into SpringBoot application.properties
echo "Inserting database parameters into SpringBoot application.properties ..."
sed "s/%LOGIN_HOST%/${LOGIN_HOST}/g" ${APP_PROPERTIES_TEMPLATE} |
    sed "s/%DB_HOST%/${DB_HOST}/g" |
    sed "s/%DB_PORT%/${DB_PORT}/g" |
    sed "s/%DB_NAME%/${DB_NAME}/g" |
    sed "s/%DB_USER%/${DB_USER}/g" |
    sed "s/%DB_PASS%/${DB_PASS}/g" > ${APP_PROPERTIES}

# Change artifact packaging type to war
echo "Changing artifact packaging type to war ..."
cd ${WORKSPACE}
sed -i "s/<name>Samsara<\/name>/<name>Samsara<\/name><packaging>war<\/packaging>/g" pom.xml