#!/bin/bash

# debug
echo "env"
env

# define job variables
START_DIR=`pwd`

# Create virtualenv for running tests
virtualenv --no-site-packages --distribute env
env/bin/pip install -U distribute
env/bin/pip uninstall --yes sentry || echo "Sentry not installed."

rm -rf env/project
mkdir -p env/project/static
cp -R src/sentry/static/sentry/ env/project/static/

# we have to make static, then install sentry program, then build locale which depends on the sentry program being there
make STATIC_DIR=env/project/static/sentry static
env/bin/python setup.py install

# find me the sentry binary
echo "DEBUG: Find the sentry binary"
find . -type f -name sentry -ls
find . -type f -name xgettext -ls

# we should not have to do this but it's scribbling outside the build dir
if [ -f /var/lib/jenkins/.sentry/sentry.conf.py ]; then
        rm -f /var/lib/jenkins/.sentry/sentry.conf.py
fi

# try this
./env/bin/sentry init

# and see if this runs
make STATIC_DIR=env/project/static/sentry SENTRY=../../env/bin/sentry locale


# create test_project environment which uses sqlite mem tables for its database
## We have no tests yet
# create config file for jenkins
cat >test_project/jenkins_settings.py <<EOF
# WE HAVE NO TESTS AND NO TEST SETTINGS AS OF THIS TIME
EOF


# run tests
. ./env/bin/activate
./env/bin/python test_project/manage.py test sentry --settings=jenkins_settings
deactivate
## We have no tests yet

# make relocatable
virtualenv --relocatable env
DEPLOY_PATH=/var/sentry/
sed -i "s:$PWD/env:$DEPLOY_PATH:" env/lib/python2.7/site-packages/*.pth || echo "Failed to rewrite files."
sed -i "s:$PWD/env:$DEPLOY_PATH:" env/lib/python2.7/site-packages/*.egg-link || echo "Failed to rewrite files."
sed -i "s:#!/usr/bin/env python2.6:#!/usr/bin/env python2.7:" env/bin/*.py || echo "Failed to rewrite files."

cp env/bin/activate tmp_activate
sed -i "s:$PWD/env:$DEPLOY_PATH:" env/bin/activate

# remove any existing debs, as they should already be signed & imported into the repo
rm -f *.deb

# build a deb
cd env
echo "building deb"
fpm \
    -n sentry-prod \
    -v $BUILD_NUMBER \
    -t deb \
    -s dir \
    --prefix $DEPLOY_PATH \
    ./
cd ..
mv env/*.deb .

# restore unmodified activate file
mv tmp_activate env/bin/activate

# sign the deb
dpkg-sig --sign builder *.deb

# load it into our apt-repository
cd /srv/repos/ubuntu && reprepro -Vb . includedeb precise $WORKSPACE/*.deb && cd -

# run chef-client on remote nodes, which will install updated packaging
# DON'T DEPLOY
#knife ssh -i ~/.ssh/socialcode-062011.pem -x ubuntu -a cloud.public_hostname "chef_environment:production AND role:sentry_server" "sudo chef-client"
