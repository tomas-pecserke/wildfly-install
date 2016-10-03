#!/bin/bash
#
#title           :wildfly-install.sh
#description     :The script to install WildFly 10.x - Java EE7 Full & Web Distribution
#more            :https://docs.jboss.org/author/display/WFLY10/Getting+Started+Guide
#author	         :Tomas Pecserke
#date            :2016-10-03T14:57+0200
#usage           :/bin/bash wildfly-install.sh
#tested-version  :10.1.0.Final
#tested-distros  :Ubuntu 16.04

VERSION=10.1.0.Final
FILENAME=wildfly-$VERSION
ARCHIVE=$FILENAME.tar.gz
DOWNLOAD_ADDRESS=http://download.jboss.org/wildfly/$VERSION/$ARCHIVE

INSTALL_ROOT=/opt
INSTALL_DIR=$INSTALL_ROOT/$FILENAME
INSTALL_DIR_NO_VERSION=$INSTALL_ROOT/wildfly

SERVICE_NAME=wildfly
SERVICE_USER=wildfly
SERVICE_GROUP=wildfly

ENVIRONMENT_FILE=/etc/default/wildfly

if [ $EUID -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

if [ ! -x /bin/systemctl ]; then
  echo "Systemd not found. This script uses systemd service to manage WildFly service."
  exit 1
fi

if [ $(java -version 2>&1 | head -n 1 | grep 1.8 -c) -ne 1 ]; then
  echo "Java 1.8 is required."
  exit 1
fi

echo "Downloading: $DOWNLOAD_ADDRESS..."
cd /tmp
if [ -e "$ARCHIVE_NAME" ]; then
  echo 'Installation file already exists.'
else
  curl -L -O $DOWNLOAD_ADDRESS
  if [ $? -ne 0 ]; then
    echo "Not possible to download installation file."
    exit 1
  fi
fi

echo "Creating user and group..."
getent group $SERVICE_GROUP > /dev/null || \
  groupadd $SERVICE_GROUP
getent passwd $SERVICE_USER > /dev/null || \
  useradd -s /bin/false -g $SERVICE_GROUP -d $INSTALL_ROOT $SERVICE_USER

echo "Installation..."
mkdir $INSTALL_DIR -p
tar -xzf $ARCHIVE -C $INSTALL_DIR --strip-components=1
chown -R $SERVICE_USER:$SERVICE_GROUP $INSTALL_DIR
chown -R $SERVICE_USER:$SERVICE_GROUP $INSTALL_DIR/
ln -s $INSTALL_DIR $INSTALL_DIR_NO_VERSION
cat > $INSTALL_DIR_NO_VERSION/bin/launch.sh << "EOF"
#!/bin/sh
if [ "x$WILDFLY_HOME" = "x" ]; then
  WILDFLY_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ "$1" == "domain" ]]; then
  $WILDFLY_HOME/bin/domain.sh -c $2 -b $3
else
  $WILDFLY_HOME/bin/standalone.sh -c $2 -b $3
fi
EOF
chmod +x $INSTALL_DIR_NO_VERSION/bin/launch.sh

echo "Registering service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << "EOF"
[Unit]
Description=The WildFly Application Server
After=syslog.target network.target
Before=httpd.service

[Service]
Environment=LAUNCH_JBOSS_IN_BACKGROUND=1
EnvironmentFile=-$ENVIRONMENT_FILE
User=$SERVICE_USER
Group=$SERVICE_GROUP
LimitNOFILE=102642
PIDFile=/var/run/$SERVICE_NAME.pid
ExecStart=$INSTALL_DIR_NO_VERSION/bin/launch.sh $WILDFLY_MODE $WILDFLY_CONFIG $WILDFLY_BIND
StandardOutput=null

[Install]
WantedBy=multi-user.target
EOF

sed -i -e 's,$INSTALL_DIR_NO_VERSION,'$INSTALL_DIR_NO_VERSION',g' /etc/systemd/system/$SERVICE_NAME.service
sed -i -e 's,$SERVICE_USER,'$SERVICE_USER',g' /etc/systemd/system/$SERVICE_NAME.service
sed -i -e 's,$SERVICE_GROUP,'$SERVICE_GROUP',g' /etc/systemd/system/$SERVICE_NAME.service
sed -i -e 's,$SERVICE_NAME,'$SERVICE_NAME',g' /etc/systemd/system/$SERVICE_NAME.service
sed -i -e 's,$ENVIRONMENT_FILE,'$ENVIRONMENT_FILE',g' /etc/systemd/system/$SERVICE_NAME.service

echo "Applying defualt configuration"
cat > $ENVIRONMENT_FILE << "EOF"
# Location of JDK
JAVA_HOME="/usr/lib/jvm/java-8-oracle"

# The configuration you want to run
WILDFLY_CONFIG=standalone-full.xml

# The mode you want to run
WILDFLY_MODE=standalone

# The amount of time to wait for startup
STARTUP_WAIT=60

## The amount of time to wait for shutdown
SHUTDOWN_WAIT=60

# The address to bind to
WILDFLY_BIND=0.0.0.0
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME

echo "Starting service..."
systemctl start $SERVICE_NAME
