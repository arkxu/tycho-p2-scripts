#!/bin/sh
# ========================================================================
# Copyright (c) 2006-2010 Intalio Inc
# ------------------------------------------------------------------------
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# and Apache License v2.0 which accompanies this distribution.
# The Eclipse Public License is available at 
# http://www.eclipse.org/legal/epl-v10.html
# The Apache License v2.0 is available at
# http://www.opensource.org/licenses/apache2.0.php
# You may elect to redistribute this code under either of these licenses. 
# ========================================================================
# Author hmalphettes
#
# Release script, mimicks the buildr release or maven release. For tycho.
# Also "deploys" generated p2-repositories.
#
# Clean
# Reads the main version number and delete '-SNAPSHOT' from it.
# Reads the buildNumber and increment it by 1. Pad it with zeros.
# Replace the context qualifier in the pom.xml by this buildNumber
# Build
# Commit and tags the sources (git or svn)
# Replace the forceContextQualifier's value by qualifier
# Commit
# git branch to checkout.
echo "Executing tycho-release.sh in the folder "`pwd`
#make sure we are at the root of the folder where the chckout actually happened.
if [ ! -d ".git" -a ! -d ".svn" ]; then
  echo "FATAL: could not find .git or .svn in the Current Directory `pwd`"
  echo "The script must execute in the folder where the checkout of the sources occurred."
  exit 2;
fi

if [ -z "$MAVEN3_HOME" ]; then
  MAVEN3_HOME=~/tools/apache-maven-3.0-beta-1
fi

if [ -d ".git" -a -z "$GIT_BRANCH" ]; then
  GIT_BRANCH=master
  export GIT_BRANCH
fi

#Base folder on the file system where the p2-repositories are deployed.
if [ -z "$BASE_FILE_PATH_P2_REPO" ]; then
  #Assume we are on the release machine logged in as the release user.
  BASE_FILE_PATH_P2_REPO=~/p2repo
fi

if [ -z "$SYM_LINK_CURRENT_NAME" ]; then
  SYM_LINK_CURRENT_NAME="current"
fi

if [ -d ".git" ]; then
  git checkout $GIT_BRANCH
  git pull origin $GIT_BRANCH
fi

if [ -n "$SUB_DIRECTORY" ]; then
  cd $SUB_DIRECTORY
fi

### Compute the build number.
#tags the sources for a release build.
reg="<version>(.*)-SNAPSHOT<\/version>"
line=`awk '{if ($1 ~ /'$reg'/){print $1}}' < pom.xml | head -1`
version=`echo "$line" | awk 'match($0, "<version>(.*)-SNAPSHOT</version>", a) { print a[1] }'`

reg2="<!--forceContextQualifier>(.*)<\/forceContextQualifier-->"
buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < pom.xml | head -1`
if [ -z "$buildNumberLine" ]; then
  echo "Could not find the build-number to use in pom.xml; The line $reg2 must be defined"
  exit 2;
fi
currentBuildrNumber=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`

#increment the context qualifier
buildNumber=`expr $currentBuildrNumber + 1`
#pad with zeros so the build number is 3 digits long
buildNumber=`printf "%03d\n" "$buildNumber"`
completeVersion="$version.$buildNumber"
export completeVersion
export version
export buildNumber
echo "Building $completeVersion"

#update the numbers for the release
sed -i "s/<!--forceContextQualifier>.*<\/forceContextQualifier-->/<forceContextQualifier>$buildNumber<\/forceContextQualifier>/" pom.xml

#### Build now
$MAVEN3_HOME/bin/mvn clean package

echo "Finished building"

### Tag the source controle
if [ -n GIT_BRANCH ]; then
  git commit pom.xml -m "Release $completeVersion"
  git tag $completeVersion
  git push origin $GIT_BRANCH
  git push origin refs/tags/$completeVersion
elif [ -d ".svn" ]; then
  svn commit pom.xml -m "Release $completeVersion"
  echo "Committed the pom.ml"
  #grab the trunk from which the checkout is done:
  svn_url=`svn info |grep URL`
  #for example: URL: http://io.intalio.com/svn/n3/intaliocrm/trunk
  svn_url=`echo "$svn_url" | awk 'match($0, "URL: (.*)/trunk", a) { print a[1] }'`
  #This should be for example: http://io.intalio.com/svn/n3/intaliocrm
  svn copy $svn_url/trunk $svn_url/tags/$completeVersion
fi

#restore the commented out forceContextQualifier
sed -i "s/<forceContextQualifier>.*<\/forceContextQualifier>/<!--forceContextQualifier>$buildNumber<\/forceContextQualifier-->/" pom.xml
if [ -d ".git" ]; then
  git commit pom.xml -m "Restore pom.xml for development"
  git push origin $GIT_BRANCH
elif [ -d ".svn" ]; then
  svn commit pom.xml -m "Restore pom.xml for development"
fi

### P2-Repository 'deployment'
# Go into each one of the folders looking for pom.xml files that packaging type is
# 'eclipse-repository'
current_dir=`pwd`;
current_dir=`readlink -f $current_dir`
reg3="<packaging>eclipse-repository<\/packaging>"
for pom in `find $current_dir -name pom.xml -type f`
do
  module_dir=`echo "$pom" | awk 'match($0, "(.*)/pom.xml", a) { print a[1] }'`
  #echo "module_dir $module_dir"
  #Look for the target/repository folder:
  #if [ -d "$module_dir/target/repository" ]; then
  if [ -d "$module_dir" ]; then
    packagingRepo=`awk '{if ($1 ~ /'$reg3'/){print $1}}' < $pom | head -1`
    if [ ! -z "$packagingRepo" ]; then
      # OK we have a repo project.
      # Let's read its group id and artifact id and make that into the base folder
      # Where the p2 repository is deployed
       artifactId=`xpath -q -e "/project/artifactId/text()" $pom`
       groupId=`xpath -q -e "/project/groupId/text()" $pom`
       if [ -z "$groupId" ]; then
         groupId=`xpath -q -e "/project/parent/groupId/text()" $pom`
       fi
       p2repoPath=$BASE_FILE_PATH_P2_REPO/`echo $groupId | tr '.' '/'`/$artifactId
       echo "Deploying $groupId:$artifactId:$completeVersion in $p2repoPath/$completeVersion"
       mkdir -p $p2repoPath
       mv "$module_dir/target/repository" "$module_dir/target/$completeVersion"
       mv "$module_dir/target/$completeVersion" $p2repoPath
       if [ -h "$p2repoPath/$SYM_LINK_CURRENT_NAME" ]; then
         rm "$p2repoPath/$SYM_LINK_CURRENT_NAME"
       fi
       ln -s $p2repoPath/$completeVersion $p2repoPath/$SYM_LINK_CURRENT_NAME
    fi
  fi
done


