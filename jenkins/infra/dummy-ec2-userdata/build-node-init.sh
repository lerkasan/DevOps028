#!/usr/bin/env bash
# set -e

function get_from_parameter_store {
    aws ssm get-parameters --names $1 --with-decryption --output text | awk '{print $4}'
}

function download_from_s3 {
    let RETRIES=$3
    until [ ${RETRIES} -lt 0 ] || [ -e "$2" ]; do
        aws s3 cp $1 $2
        let "RETRIES--"
        sleep 5
    done
    if [ ! -e "$2" ]; then
        echo "An error occurred during downloading file by URL $1"
        exit 1
    fi
}

export AWS_DEFAULT_REGION="us-west-2"
export AWS_SECRET_ACCESS_KEY=`get_from_parameter_store "SECRET_ACCESS_KEY"`
export AWS_ACCESS_KEY_ID=`get_from_parameter_store "ACCESS_KEY_ID"`

export DB_HOST=`ifconfig | grep "inet addr" | grep -v -e "127.0.0.1" -e "10.0.2" | awk '{print $2}' | awk -F':' '{print $2}'`
export DB_PORT="5432"
export DB_NAME=`get_from_parameter_store "DB_NAME"`
export DB_USER=`get_from_parameter_store "DB_USER"`
export DB_PASS=`get_from_parameter_store "DB_PASS"`
export LOGIN_HOST="localhost"
ALLOWED_LAN=`echo ${DB_HOST}/24`

BUCKET_NAME="ansible-demo1"
OS_USERNAME=`whoami`

DEMO_DIR="demo1"
PROJECT_SRC_DIR="/home/${OS_USERNAME}/${DEMO_DIR}/DevOps028"
WEB_APP_FILENAME="Samsara-1.3.5.RELEASE.jar"
REPO_URL="https://github.com/lerkasan/DevOps028.git"

JDK_FILENAME="jdk-8u144-linux-x64.tar.gz"
JDK_URL="s3://${BUCKET_NAME}/${JDK_FILENAME}"
JDK_INSTALL_DIR="/usr/lib/jvm"

MAVEN_VERSION="3.5.0"
MAVEN_FILENAME="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
MAVEN_URL="s3://${BUCKET_NAME}/${MAVEN_FILENAME}"
MAVEN_INSTALL_DIR="/usr/local/maven"
MAVEN_HOME="${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}"

LIQUIBASE_PATH="${PROJECT_SRC_DIR}/liquibase"
LIQUIBASE_BIN_DIR="${LIQUIBASE_PATH}/bin"
LIQUIBASE_PROPERTIES_TEMPLATE="${LIQUIBASE_PATH}/liquibase.properties.template"
LIQUIBASE_PROPERTIES="${LIQUIBASE_PATH}/liquibase.properties"
LIQUIBASE_FILENAME="liquibase-3.5.3-bin.tar.gz"
LIQUIBASE_CHANGELOG_FILENAME="liquibase-changelog.tar.gz"
LIQUIBASE_URL="s3://${BUCKET_NAME}/${LIQUIBASE_FILENAME}"

POSTGRES_JDBC_DRIVER_FILENAME="postgresql-42.1.4.jar"
POSTGRES_JDBC_DRIVER_URL="s3://${BUCKET_NAME}/${POSTGRES_JDBC_DRIVER_FILENAME}"

UPLOAD_DIR="/home/${OS_USERNAME}/${DEMO_DIR}/upload"
DOWNLOAD_DIR="/home/${OS_USERNAME}/${DEMO_DIR}/download"
DOWNLOAD_RETRIES=5

# Install Python-Pip, Git, PostgreSQL, AWS cli
sudo yum -y update
sudo yum -y install epel-release
sudo yum -y install python python-pip git mc postgresql-server
sudo `which pip` install --upgrade pip
sudo `which pip` install awscli

POSTGRES_CONF_UP=`sudo find /var/lib -name "pgsql*" | sort -u | head -n 1`
POSTGRES_CONF_DIR="${POSTGRES_CONF_UP}/data"
POSTGRES_SAMPLE_CONF_DIR=`sudo find /usr/share -name "pgsql*" | sort -u | head -n 1`

export PGDATA=${POSTGRES_CONF_DIR}
if [ `sudo ls -lh "${POSTGRES_CONF_UP}/data" | wc -l` -eq 1 ]; then
    sudo service postgresql initdb
fi

# Change Postgres config files
sudo cp "${POSTGRES_SAMPLE_CONF_DIR}/postgresql.conf.sample" "${POSTGRES_CONF_DIR}/postgresql.conf"
sudo chown postgres:postgres "${POSTGRES_CONF_DIR}/postgresql.conf"
sudo -u postgres sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '${DB_HOST}, 127.0.0.1'/g" "${POSTGRES_CONF_DIR}/postgresql.conf"
sudo -u postgres sed -i "s/port = 5432/port = ${DB_PORT}/g" "${POSTGRES_CONF_DIR}/postgresql.conf"
echo -e "data_directory = '${POSTGRES_CONF_DIR}'" | sudo -u postgres tee --append "${POSTGRES_CONF_DIR}/postgresql.conf"
echo -e "hba_file = '${POSTGRES_CONF_DIR}/pg_hba.conf'" | sudo -u postgres tee --append "${POSTGRES_CONF_DIR}/postgresql.conf"
# Add permission for DB_USER to connect to DB_NAME
echo -e "local \t all \t postgres \t\t \t\t \t\t peer \n host \t ${DB_NAME} \t ${DB_USER} \t\t ${ALLOWED_LAN} \t\t md5" | sudo -u postgres tee "${POSTGRES_CONF_DIR}/pg_hba.conf"

sudo service postgresql restart

# Create database and db_user
sudo -u postgres createdb ${DB_NAME}
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} to ${DB_USER};"

# Clone sources from repo
mkdir -p ${DEMO_DIR}
cd ${DEMO_DIR}
git clone ${REPO_URL}

mkdir -p ${DOWNLOAD_DIR}
mkdir -p ${UPLOAD_DIR}

# Download and install JDK
mkdir -p ${JDK_INSTALL_DIR}
if [ ! -e "${DOWNLOAD_DIR}/${JDK_FILENAME}" ]; then
    download_from_s3 "${JDK_URL}" "${DOWNLOAD_DIR}/${JDK_FILENAME}" ${DOWNLOAD_RETRIES}
fi
if [ -e "${DOWNLOAD_DIR}/${JDK_FILENAME}" ]; then
    sudo tar -xzf "${DOWNLOAD_DIR}/${JDK_FILENAME}" -C "${JDK_INSTALL_DIR}"
fi

export JAVA_HOME=`find ${JDK_INSTALL_DIR} -name java | grep -v -e "openjdk" -e "jre" | head -n 1 | rev | cut -c 10- | rev`
export PATH=${JAVA_HOME}/bin:${PATH}

sudo alternatives --install /usr/bin/java java "${JAVA_HOME}/bin/java" 2
sudo alternatives --install /usr/bin/javac javac "${JAVA_HOME}/bin/javac" 2
sudo alternatives --set java "${JAVA_HOME}/bin/java"
sudo alternatives --set javac "${JAVA_HOME}/bin/javac"

# Download and install Maven
sudo mkdir -p ${MAVEN_INSTALL_DIR}
if [ ! -e "${DOWNLOAD_DIR}/${MAVEN_FILENAME}" ]; then
    download_from_s3 "${MAVEN_URL}" "${DOWNLOAD_DIR}/${MAVEN_FILENAME}" ${DOWNLOAD_RETRIES}
fi
if [ -e "${DOWNLOAD_DIR}/${MAVEN_FILENAME}" ]; then
    sudo tar -xzf "${DOWNLOAD_DIR}/${MAVEN_FILENAME}" -C ${MAVEN_INSTALL_DIR}
fi
sudo ln -s "${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}" "${MAVEN_INSTALL_DIR}/default"

export M2_HOME=${MAVEN_HOME}
export PATH=${M2_HOME}/bin:${PATH}

sudo alternatives --install "/usr/bin/mvn" "mvn" "${MAVEN_INSTALL_DIR}/default/bin/mvn" 20000
sudo alternatives --set mvn "${MAVEN_INSTALL_DIR}/default/bin/mvn"
sudo chown -R root:root ${MAVEN_INSTALL_DIR}

# Upload Liquibase changelog to AWS S3
if [ ! -e "${UPLOAD_DIR}/${LIQUIBASE_CHANGELOG_FILENAME}" ]; then
    tar -czf "${UPLOAD_DIR}/${LIQUIBASE_CHANGELOG_FILENAME}" ${LIQUIBASE_PATH}
fi
aws s3 cp "${UPLOAD_DIR}/${LIQUIBASE_CHANGELOG_FILENAME}" "s3://${BUCKET_NAME}/${LIQUIBASE_CHANGELOG_FILENAME}"

# Download Liquibase binaries and PostgreSQL JDBC driver
mkdir -p ${LIQUIBASE_BIN_DIR}
if [ ! -e "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ]; then
    download_from_s3 "${LIQUIBASE_URL}" "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ${DOWNLOAD_RETRIES}
    if [ -e "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ]; then
        tar -xzf "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" -C "${LIQUIBASE_BIN_DIR}"
    fi
fi

if [ ! -e "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ]; then
    download_from_s3 "${POSTGRES_JDBC_DRIVER_URL}" "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ${DOWNLOAD_RETRIES}
fi

# Update database using Liquibase
sed "s/%LOGIN_HOST%/${LOGIN_HOST}/g" ${LIQUIBASE_PROPERTIES_TEMPLATE} |
    sed "s/%DB_HOST%/${DB_HOST}/g" |
    sed "s/%DB_PORT%/${DB_PORT}/g" |
    sed "s/%DB_NAME%/${DB_NAME}/g" |
    sed "s/%DB_USER%/${DB_USER}/g" |
    sed "s/%DB_PASS%/${DB_PASS}/g" > ${LIQUIBASE_PROPERTIES}

cd ${LIQUIBASE_BIN_DIR}
./liquibase --changeLogFile=../changelogs/changelog-main.xml --defaultsFile=../liquibase.properties update

# Build package with maven and upload it to aws s3
cd ${PROJECT_SRC_DIR}
mvn clean package
cp target/${WEB_APP_FILENAME} ${UPLOAD_DIR}/${WEB_APP_FILENAME}
aws s3 cp ${UPLOAD_DIR}/${WEB_APP_FILENAME} s3://${BUCKET_NAME}/${WEB_APP_FILENAME}

java -jar target/${WEB_APP_FILENAME}