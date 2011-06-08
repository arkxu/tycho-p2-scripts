#!/bin/bash -e
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
# Release script, takes care of auto-inc for buildr's Buildfile, commit tagging for svn and git
# Then invoke buildr package and deploys the generated debs in the specified repositories
#
# Load the computed build environment
# Then invoke maven or build

env_file=`pwd`
env_file="$env_file/computed-build-environment"
if [ ! -f "$env_file" ]; then
  SCRIPT=$(readlink -f $0)
  # Absolute path this script is in.
  SCRIPTPATH=`dirname $SCRIPT`
  $SCRIPTPATH/compute-environment.sh
fi
if [ ! -f "$env_file" ]; then
  currentdir = `pwd`
  echo "Could not find the file $currentdir/computed-build-environment was compute-environment.sh correctly executed?"
  exit 127
fi
chmod +x "$env_file"
. "$env_file"

if [ ! -d "$WORKSPACE_MODULE_FOLDER" ]; then
  echo "The constant WORKSPACE_MODULE_FOLDER doaes not exist. Was compute-environment.sh correctly executed?"
  exit 127
fi
echo "WORKSPACE_MODULE_FOLDER=$WORKSPACE_MODULE_FOLDER"
cd "$WORKSPACE_MODULE_FOLDER"
echo "At the moment: "`pwd`

#Run the deb generation
function generate_debs() {
  if [ -z "$DISABLE_DEB_GENERATION" ]; then
    path_to_deb_generation_script="$SCRIPTPATH/../osgi-features-to-debian-package/generate-and-collect-osgi-debs.sh"
    if [ ! -f "$path_to_deb_generation_script" ]; then
      #try a second location.
      path_to_deb_generation_script=$SCRIPTPATH/osgi-features-to-debian-package/generate-and-collect-osgi-debs.sh
    fi
    if [ ! -f "$path_to_deb_generation_script" ]; then
      echo "$path_to_deb_generation_script does not exist."
      echo "Unable to find the shell script in charge of generating the debian packages"
      exit 2;
    fi
    echo "Executing $path_to_deb_generation_script"
    $path_to_deb_generation_script
  else
    echo "No debian packages to build as the constant DEB_COLLECT_DIR is not defined."
  fi
}

if [ -n "$ROOT_POM" ]; then
  #update the numbers for the release
  sed -i "s/<!--forceContextQualifier>.*<\/forceContextQualifier-->/<forceContextQualifier>$buildNumber<\/forceContextQualifier>/" $ROOT_POM
  #### Build now
  $MAVEN3_HOME/bin/mvn -f $ROOT_POM clean verify -Dmaven.repo.local=$LOCAL_REPOSITORY
elif [ -f Buildfile ]; then
  #update the numbers for the release
  sed -i "s/$buildNumberLine/VERSION_NUMBER=\"$completeVersion\"/" Buildfile
  buildr package
else
  echo "No pom.xml and no Buildfile: nothing to build?"
fi

generate_debs

