#!/usr/bin/env bash
#set -e

# DB_SOURCE options: localhost or aws_rds
DB_SOURCE="aws_rds"

export AWS_ACCESS_KEY_ID="---------------CHANGE_ME---------------"
export AWS_SECRET_ACCESS_KEY="-----------CHANGE_ME---------------"
export AWS_DEFAULT_REGION="us-west-2"

export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export M2_HOME="/usr/share/maven"

export DB_NAME="auradb"
export DB_USER="aura"
export DB_PASS="mysecretpassword"
export DB_HOST=`ifconfig | grep "inet " | grep -v -e "127.0.0.1" -e "10.0.2" | awk '{print $2}'`
export DB_PORT="5432"
export LOGIN_HOST="localhost"
DB_INSTANCE_ID="vagrantdemo"
DB_INSTANCE_CLASS="db.t2.micro"
DB_ENGINE="postgres"
ALLOWED_LAN=`echo ${DB_HOST}/24`

OS_USERNAME=`whoami`
BUCKET_NAME="ansible-demo1"
PROJECT_DIR="/home/${OS_USERNAME}/demo1"

JDK_FILENAME="jdk-8u144-linux-x64.tar.gz"
JDK_URL="s3://${BUCKET_NAME}/${JDK_FILENAME}"
JDK_INSTALL_DIR="/usr/lib/jvm"

APPLICATION_PROPERTIES="${PROJECT_DIR}/src/main/resources/application.properties"
APPLICATION_PROPERTIES_TEMPLATE="${PROJECT_DIR}/src/main/resources/application.properties.template"

LIQUIBASE_BIN_DIR="${PROJECT_DIR}/liquibase/bin"
LIQUIBASE_PATH="/home/${OS_USERNAME}/demo1/liquibase"
LIQUIBASE_PROPERTIES_TEMPLATE="${LIQUIBASE_PATH}/liquibase.properties.template"
LIQUIBASE_PROPERTIES="${LIQUIBASE_PATH}/liquibase.properties"
LIQUIBASE_FILENAME="liquibase-3.5.3-bin.tar.gz"
LIQUIBASE_S3_URL="s3://${BUCKET_NAME}/${LIQUIBASE_FILENAME}"
LIQUIBASE_URL="https://github.com/liquibase/liquibase/releases/download/liquibase-parent-3.5.3/liquibase-3.5.3-bin.tar.gz"

POSTGRES_JDBC_DRIVER_URL="https://jdbc.postgresql.org/download/postgresql-42.1.4.jar"
POSTGRES_JDBC_DRIVER_FILENAME="postgresql-42.1.4.jar"

DOWNLOAD_DIR="/home/${OS_USERNAME}/${DEMO_DIR}/download"
DOWNLOAD_RETRIES=5

function download_from_s3 {
#    let RETRIES=$3
    (( RETRIES=$3 ))
    if [ ! -e "$2" ]; then
        until [ ${RETRIES} -lt 0 ] || [ -e "$2" ]; do
            aws s3 cp "$1" "$2"
            (( "RETRIES--" )) # let "RETRIES--"
            sleep 5
        done
        if [ ! -e "$2" ]; then
            echo "An error occurred during downloading file by URL $1"
            exit 1
        fi
    else
        echo "INFO: Skipping download. This file exists."
    fi
}

# Install Maven, PostgreSQL, AWScli
#sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade

# Install AWScli
sudo apt-get -y install awscli

# Download and install JDK8 - old approach
#echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
#echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
#sudo apt-get -qq -y install oracle-java8-set-default
#export JAVA_HOME="/usr/lib/jvm/java-8-oracle"

# Download and install JDK8 - new approach
#sudo apt-get -y install openjdk-8-jdk openjdk-8-jre
#export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
#export JRE_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre

# Download and install JDK8 from a file stored at AWS S3
mkdir -p "${DOWNLOAD_DIR}"
sudo mkdir -p "${JDK_INSTALL_DIR}"

download_from_s3 "${JDK_URL}" "${DOWNLOAD_DIR}/${JDK_FILENAME}" ${DOWNLOAD_RETRIES}

if [ -e "${DOWNLOAD_DIR}/${JDK_FILENAME}" ]; then
    sudo tar -xzf "${DOWNLOAD_DIR}/${JDK_FILENAME}" -C "${JDK_INSTALL_DIR}"
fi

export JAVA_HOME=`find ${JDK_INSTALL_DIR} -name java | grep -v -e "openjdk" -e "jre" | head -n 1 | rev | cut -c 10- | rev`
export PATH=${JAVA_HOME}/bin:${PATH}

sudo update-alternatives --install /usr/bin/java java "${JAVA_HOME}/bin/java" 2
sudo update-alternatives --install /usr/bin/javac javac "${JAVA_HOME}/bin/javac" 2
sudo update-alternatives --set java "${JAVA_HOME}/bin/java"
sudo update-alternatives --set javac "${JAVA_HOME}/bin/javac"

# Install Maven, MC
sudo apt-get -y install maven mc

# If DB_SOURCE is set to localhost then install local Postgres server, else create instance at RDS
if [[ -z `echo ${DB_SOURCE} | grep -v localhost` ]]; then

    # Install Postgres
    sudo apt-get -y install postgresql

    # Change listen address binding to Vagrant ethernet interface to provide host machine connectivity to postgres through forwarded port
    POSTGRES_CONF_PATH=`find /etc/postgresql -name "postgresql.conf"`
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '${DB_HOST}, 127.0.0.1'/g" ${POSTGRES_CONF_PATH}
    sudo sed -i "s/port = 5432/port = ${DB_PORT}/g" ${POSTGRES_CONF_PATH}

    # Add permission for DB_USER to connect to DB_NAME from host machine by IP from vagrant private_network
    PG_HBA_PATH=`find /etc/postgresql -name "pg_hba.conf"`
    echo -e "host \t ${DB_NAME} \t ${DB_USER} \t\t ${ALLOWED_LAN} \t\t md5" | sudo -u postgres tee -a ${PG_HBA_PATH}
    sudo service postgresql restart

    # Create local database and db_user
    sudo -u postgres createdb ${DB_NAME}
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} to ${DB_USER};"

else
    # Create database at RDS
    EXISTING_DB_INSTANCE_INFO=`aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output text | grep ${DB_INSTANCE_ID}`
    if [[ -z ${EXISTING_DB_INSTANCE_INFO} ]]; then
        aws rds create-db-instance --db-instance-identifier ${DB_INSTANCE_ID} --db-instance-class ${DB_INSTANCE_CLASS} --engine ${DB_ENGINE} --backup-retention-period 0 --storage-type gp2 --allocated-storage 5 --db-name ${DB_NAME} --master-username ${DB_USER} --master-user-password ${DB_PASS}
        aws rds wait db-instance-available --db-instance-identifier ${DB_INSTANCE_ID}
    fi
    EXISTING_DB_INSTANCE_INFO=`aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output text | grep ${DB_INSTANCE_ID}`

    # Start database instance if needed
    DB_STATUS=`echo ${EXISTING_DB_INSTANCE_INFO} | awk '{print $4}'`
    if [[ ${DB_STATUS} == "stopped" ]]; then
        aws rds start-db-instance --db-instance-identifier ${DB_INSTANCE_ID}
        aws rds wait db-instance-available --db-instance-identifier ${DB_INSTANCE_ID}
    fi
    export DB_HOST=`echo ${EXISTING_DB_INSTANCE_INFO} | awk '{print $2}'`
    export DB_PORT=`echo ${EXISTING_DB_INSTANCE_INFO} | awk '{print $3}'`
fi

# Download Liquibase binaries and PostgreSQL JDBC driver
mkdir -p ${LIQUIBASE_BIN_DIR}

download_from_s3 "${LIQUIBASE_S3_URL}" "${DOWNLOAD_DIR}/${LIQUIBASE_FILENAME}" ${DOWNLOAD_RETRIES}

if [ -e "${DWONLOAD_DIR}/${LIQUIBASE_FILENAME}" ]; then
    tar -xzf "${DOWNLOAD_DIR}/${LIQUIBASE_FILENAME}" -C "${LIQUIBASE_BIN_DIR}"
fi

## -- by default wget makes 20 tries to download file if there is an error response from server (or use --tries=40 to increase retries amount).
## -- Exceptions are server responses CONNECTIONS_REFUSED and NOT_FOUND - in these cases wget will not retry download
if [ ! -e "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ]; then
    wget "${POSTGRES_JDBC_DRIVER_URL}" -O "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}"
#    download_from_s3 "${POSTGRES_JDBC_DRIVER_URL}" "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ${DOWNLOAD_RETRIES}
fi

# Update database using Liquibase
sed "s/%LOGIN_HOST%/${LOGIN_HOST}/g" "${LIQUIBASE_PROPERTIES_TEMPLATE}" |
    sed "s/%DB_HOST%/${DB_HOST}/g" |
    sed "s/%DB_PORT%/${DB_PORT}/g" |
    sed "s/%DB_NAME%/${DB_NAME}/g" |
    sed "s/%DB_USER%/${DB_USER}/g" |
    sed "s/%DB_PASS%/${DB_PASS}/g" > "${LIQUIBASE_PROPERTIES}"

cd "${LIQUIBASE_BIN_DIR}"
./liquibase --changeLogFile=../changelogs/changelog-main.xml --defaultsFile=../liquibase.properties update

# Update application.properties using template
sed "s/%DB_HOST%/${DB_HOST}/g" "${APPLICATION_PROPERTIES_TEMPLATE}" |
    sed "s/%DB_PORT%/${DB_PORT}/g" |
    sed "s/%DB_NAME%/${DB_NAME}/g" |
    sed "s/%DB_USER%/${DB_USER}/g" |
    sed "s/%DB_PASS%/${DB_PASS}/g" > "${APPLICATION_PROPERTIES}"

cd "${PROJECT_DIR}"
mvn clean package
java -jar target/*.jar
#nohup java -jar target/*.jar &


