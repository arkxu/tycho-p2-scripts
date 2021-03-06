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

### P2-Repository 'deployment'
# Go into each one of the folders looking for pom.xml files that packaging type is
# 'eclipse-repository'
# Add a file to identify the build and the version. eventually we could even add some html pages here.
# Then move the repository in its 'final' destination. aka the deployment.
env_file=`pwd`
env_file="$env_file/computed-build-environment"
if [ ! -f "$env_file" ]; then
  currentdir = `pwd`
  echo "Could not find the file $currentdir/computed-build-environment was compute-environment.sh correctly executed?"
  exit 127
fi
chmod +x "$env_file"
. "$env_file"

cd $WORKSPACE_MODULE_FOLDER
echo $WORKSPACE_MODULE_FOLDER
echo "Executing deployment of the p2 repositories in "`pwd`

#Finds all the installable units for which there is a deb package.
#Create 2 arrays: The list of iu_id_and_version that contains ${iu_id}_${iu_version}
#The list of deb files absolute path. (There are no associative arrays in bash)
function create_ius_and_debs_array() {
  create_ius_and_debs_array_was_called="true"
  deb_published_ius=()
  deb_files=()
  for csv_file in `find $WORKSPACE_MODULE_FOLDER -type f -name *.deb-ius.csv`; do
    #Make sure we only find the csv files that are in the generated target directories
    local dirn=$(basename `dirname $csv_file`)
    [ "$dirn" != "target" ] && continue
    local filename=`basename $csv_file`
    local iu_id_and_version=`echo "$filename" | sed 's/\.deb-ius\.csv//'`
    local iu_id=`echo "$filename" | sed -nr 's/(.*)_.*/\1/p'`
    #for example: cloud.iaas.metering.f.feature.group_3.1.1.201106061022.deb-ius.csv
    #echo "filename=$filename - iu_id_and_version=$iu_id_and_version ${#deb_published_ius[*]}"

    #Read the csv file to extract the name of the deb file:
    #intalio-cloud-platform-3.1.1.201106061022.deb,intalio-cloud-platform,3.1.1.201106061022,cloud.platform,3.1.1.201106061022,"Intalio|Cloud Platform"
    #line=`sed -n '/cloud\.platform/p' $csv_file`
    line=`grep "$iu_id" $csv_file`
    directory=`dirname $csv_file`
    if [ -n "$line" ]; then
      deb_file=`echo $line | cut -d',' -f1`
    fi
    if [ -z "deb_file" ]; then
      #we should not be here but we can still default on the single deb file found in the target folder.
      deb_file=$(basename `ls $directory/*.deb | head -1`)
    fi
    if [ -z "deb_file" ]; then
      echo "Error? Found a .deb-ius.csv file but no associated deb file"
      continue
    fi
    #echo "grep "$iu_id" -> $directory/$deb_file"
    deb_published_ius[${#deb_published_ius[*]}]="$iu_id_and_version"
    deb_files[${#deb_files[*]}]="$directory/$deb_file"
  done
  if [ -z "DEBUG" ]; then
    echo "csv_files items and indexes:"
    for index in ${!deb_published_ius[*]}; do
      echo "$index: ${deb_published_ius[$index]} -> ${deb_files[$index]}"
      #printf "%4d: %s\n" $index ${deb_published_ius[$index]}
    done
  fi
}

#Returns the deb file for a iuid_version.
function get_deb_file() {
  [ -z "$create_ius_and_debs_array_was_called" ] && create_ius_and_debs_array
  for index in ${!deb_published_ius[*]}; do
    if [ ${deb_published_ius[$index]} == $1 ]; then
      echo "${deb_files[$index]}"
      return
    fi
  done
}

#Generates the p2.index file as recommended here:
#http://wiki.eclipse.org/Equinox/p2/p2_index
#Expects one argument: a folder that is a built repository.
function write_p2_index() {
  if [ ! -d "$1" ]; then
    echo "Expecting the argument $1 to be a valid folder"
    exit 127
  fi
  if [ -f "$1/artifacts.jar" ]; then
    local artifacts="artifacts.xml"
  elif [ -f "$1/artifacts.xml" ]; then
    local artifacts="artifacts.xml"
  elif [ -f "$1/compositeArtifacts.xml" ]; then
    local artifacts="compositeArtifacts.xml"
  elif [ -f "$1/compositeArtifacts.jar" ]; then
    local artifacts="compositeArtifacts.xml"
  else
    echo "WARN Could not find artifacts.* or compositeArtifacts inside $1: this repository is not complete?"
    exit 123
  fi

  if [ -f "$1/content.jar" ]; then
    local content="content.xml"
  elif [ -f "$1/content.xml" ]; then
    local content="content.xml"
  elif [ -f "$1/compositeContent.xml" ]; then
    local content="compositeContent.xml"
  elif [ -f "$1/compositeContent.jar" ]; then
    local content="compositeContent.xml"
  else
    echo "WARN: Could not find content.* or compositeContent inside $1: this repository is not complete?"
    exit 123
  fi

  echo "# p2.index generated on ${timestamp_and_id}
version = 1
artifact.repository.factory.order = ${artifacts}, !
metadata.repository.factory.order = ${content}, !" > $1/p2.index
}

#Find the p2 repositories that are built by maven/tycho
#Populates the array built_p2_repositories
function find_built_p2_repositories() {
  find_built_p2_repositories_was_called="true"
  built_p2_repositories=()
  if [ -f "Buildfile" -a -d "target/repository" ]; then
    built_p2_repositories[${#built_p2_repositories[*]}]=`pwd`"/target/repository"
    write_p2_index `pwd`"/target/repository"
  else
    reg3="<packaging>eclipse-repository<\/packaging>"
    reg4="<packaging>eclipse-update-site<\/packaging>"
    for pom in `find $WORKSPACE_MODULE_FOLDER -name pom.xml -type f`; do
      module_dir=`echo "$pom"`
      module_dir=${module_dir%%/pom.xml}
      #echo "module_dir $module_dir"
      #Look for the target/repository folder:
      #if [ -d "$module_dir/target/repository" ]; then
      if [ -d "$module_dir" ]; then
        packagingRepo=`awk '{if ($1 ~ /'$reg3'/){print $1}}' < $pom | head -1`
        repository_or_site='repository'
        if [ -z "$packagingRepo" ]; then
          packagingRepo=`awk '{if ($1 ~ /'$reg4'/){print $1}}' < $pom | head -1`
          repository_or_site='site'
        fi
        if [ -n "$packagingRepo" ]; then
          # OK we have a repo project.
          built_repository="$module_dir/target/$repository_or_site"
          if [ -d "$built_repository" ]; then # make sure the repo is built
            built_p2_repositories[${#built_p2_repositories[*]}]="$built_repository"
            write_p2_index $built_repository
          fi
        fi
      fi
    done
  fi
}

#Compute the deployment location of one p2 repo
function compute_p2_repository_deployment_folder() {
  local module_dir=${1%/*/*}
  local pom=$module_dir/pom.xml
  if [ ! -f $pom ]; then
    if [ -z "$ROOT_POM" -a -f "$module_dir/Buildfile" ]; then
      groupId="$grpIdForCompositeRepo"
    else
      echo "$1 must be a directory that contains a pom.xml file" 1>&2
      exit 12
    fi
  else
    # Let's read its group id and artifact id and make that into the base folder
    # Where the p2 repository is deployed
    artifactId=`xpath -q -e "/project/artifactId/text()" $pom`
    if [ -z "$groupId" ]; then
      groupId=`xpath -q -e "/project/groupId/text()" $pom`
    fi
    if [ -z "$groupId" ]; then
      groupId=`xpath -q -e "/project/parent/groupId/text()" $pom`
    fi
    local repository_suffix=`xpath -q -e "/project/properties/repositorySuffix/text()" $pom`
    local repository_override_suffix=`xpath -q -e "/project/properties/repositoryOverrideSuffix/text()" $pom`
    local groupIdSlashed=`echo $groupId | tr '.' '/'`
    if [ -n "$repository_suffix" ]; then
      local groupIdSlashed="$groupIdSlashed/$repository_suffix"
    fi
    if [ -n "$repository_override_suffix" ]; then
      # delete the last token in the groupId and replace it by the override
      # for example org.intalio.eclipse.jetty with override 'equinox' will deploy in org/intalio/eclipse/equinox
      local groupIdSlashed=`dirname $groupIdSlashed`/$repository_override_suffix
    fi
  fi 
  [ -z "$groupIdSlashed" ] && local groupIdSlashed=`echo $groupId | tr '.' '/'`
  if [ -z "$BRANCH_FOLDER_NAME" ]; then
    echo "Warning unknown BRANCH_FOLDER_NAME. Using 'unknown_branch' by default" 1>&2
    BRANCH_FOLDER_NAME='unknown_branch_name'
  fi
  if [ -z "$completeVersion" ]; then
    echo "Warning unknown completeVersion Using 'unknown_version' by default" 1>&2
    completeVersion='unknown_version'
  fi
  local p2repoPath=$BASE_FILE_PATH_P2_REPO/$groupIdSlashed/$BRANCH_FOLDER_NAME
  local p2repoPathComplete="$p2repoPath/$completeVersion"

  if  [ -n "$P2_DEPLOYMENT_FOLDER_NAME" ]; then
    echo "Using P2_DEPLOYMENT_FOLDER_NAME=$P2_DEPLOYMENT_FOLDER_NAME for the final name of the folder where the repository is deployed." 1>&2
    p2repoPathComplete="$p2repoPath/$P2_DEPLOYMENT_FOLDER_NAME"
  else
    P2_DEPLOYMENT_FOLDER_NAME=$completeVersion
  fi
  #Generate the build signature file that will be read by other builds via tycho-resolve-p2repo-versions.rb
  #to identify the actual version of the repo used as a dependency.
  version_built_file=$1/version_built.properties
  echo "artifact=$groupId:$artifactId" > $version_built_file
  echo "version=$completeVersion" >> $version_built_file
  echo "built=$timestamp_and_id" >> $version_built_file
  echo "Deploying $groupId:$artifactId:$completeVersion in $p2repoPathComplete" 1>&2
  echo "$p2repoPathComplete"
}

#Computes the array of deployment folders associated to each built p2 repositories
#They are listed in the arrray p2_repositories_deployment_folders
function compute_p2_repositories_deployment_folders() {
  compute_p2_repositories_deployment_folders_was_called=true
  [ -z "$find_built_p2_repositories_was_called" ] && find_built_p2_repositories
  p2_repositories_deployment_folders=()
  for built_p2_repository in ${built_p2_repositories[*]}; do
    destination=`compute_p2_repository_deployment_folder $built_p2_repository | tail -n 1`
    echo "destination=$destination"
    p2_repositories_deployment_folders[${#p2_repositories_deployment_folders[*]}]="$destination"
  done
}


#Generates the apt indexes for a given folder
#Requires the path to the folder to archive as an argument
#Requires the apt-ftparchive binary to be installed.
function apt_index() {
  local target_dir="$1"
  local packages_rel_dir="debs"
  if [ -n "$2" ]; then
    packages_rel_dir="$2"
  fi
  if [ ! -d "$target_dir" ]; then
    echo "The directory $target_dir does not exist."
    exit 12
  fi
  if [ -d "$target_dir/$packages_rel_dir" ]; then
    local curr_dir=`pwd`
    cd $target_dir
    apt-ftparchive packages $packages_rel_dir > $packages_rel_dir/Packages
    cd $curr_dir
  fi
}


#Expects the path to a built p2 repository folder.
#Locate the IUs that are associated to a debian file.
#Copies the deb file into a sub-folder 'debs' inside the built repository.
function populate_built_p2_repository_with_debs() {
  local built_repository="$1"
  if [ ! -d "$built_repository" ]; then
    echo "The directory $built_repository does not exist."
    exit 12
  fi
  [ -f "$built_repository/Packages" ] && rm -rf "$built_repository/Packages"
  [ -f "$built_repository/Packages.gz" ] && rm -rf "$built_repository/Packages.gz"
  [ -d "$built_repository/debs" ] && rm -rf "$built_repository/debs"

  #Now we need to locate the deb files that are associated to plugins/features/products published in this repository
  #Once located we copy them inside the debs folder of this repository.
  #Then we call the apt-get indexer to generate the index for those deb files.
  #how do we know what plugin, product or features are published here?
  #we iterate over the file names hugues says.
  for subname in "$built_repository/plugins" "$built_repository/features"; do
    #The IUs of the features has the suffix '.feature.group' that does not appear in the file name
    #but does appear in the IU id:
    [ "$subname" = "features" ] && iu_suffix=".feature.group" || iu_suffix=""
    local any_jars=`find $built_repository/$subname -type f -name *.jar`
    if [ "$any_jars" ]; then
      for jarfile in `ls $built_repository/$subname/*.jar 2>/dev/null`; do
        local jarfile_name=`basename $jarfile`
        local iu_id=`echo "$jarfile_name" | sed -nr 's/(.*)_.*\.jar/\1/p'`$iu_suffix
        local iu_version=`echo "$jarfile_name" | sed -nr 's/.*_(.*)\.jar/\1/p'`
        local iuid_version=$iu_id"_"$iu_version
        local deb_file=`get_deb_file $iuid_version`
        #[ -n "$DEBUG" ] && echo "iu_id $iuid_version -> deb $deb_file"
        if [ -n "$deb_file" ]; then
          mkdir -p "$built_repository/debs"
          cp $deb_file "$built_repository/debs"
        fi
      done
    fi
    local any_products=`find $built_repository/binary -type f -name *.executable.gtk.linux.x86_64_*`
    if [ "$any_products" ]; then
      #take care of the products. we use the name of the executable: 
      #for example binary/cloud.platform.executable.gtk.linux.x86_64_3.1.1.549
      for execzip in `ls $built_repository/binary/*.executable.gtk.linux.x86_64_* 2>/dev/null`; do
        local execfile_name=`basename $execzip`
        local iuid_version=`echo "$execfile_name" | sed 's/\.executable\.gtk\.linux\.x86_64_/_/'`
        local deb_file=`get_deb_file $iuid_version`
        [ -n "$DEBUG" ] && echo "$execfile_name: $iuid_version -> $deb_file"
        if [ -n "$deb_file" ]; then
          mkdir -p "$built_repository/debs"
          cp $deb_file "$built_repository/debs"
        fi
      done
    fi
  done

  if [ -d "$built_repository/debs" ]; then
    #let's index this repository of deb packages:
    apt_index $built_repository
  fi

}

#Locate the IUs that are associated to a debian file.
#Copies the deb file into a sub-folder 'debs' inside the built repository.
function populate_built_p2_repositories_with_debs() {
  populate_built_p2_repositories_with_debs_was_called="true"
  if [ -z "$ROOT_POM" ]; then
    local any_debs=`find target -type f -name *.deb`
    if [ "$any_debs" ]; then
      for debfile in `ls target/*.deb 2>/dev/null`; do
        mkdir -p target/repository/debs
        cp debfile target/repository/debs
      done
      [ -d "target/repository/debs" ] && apt_index target/repository/debs
    fi
  else
    [ -z "$create_ius_and_debs_array_was_called" ] && create_ius_and_debs_array
    [ -z "$find_built_p2_repositories_was_called" ] && find_built_p2_repositories

    for built_repository in ${built_p2_repositories[*]}; do
      populate_built_p2_repository_with_debs $built_repository
    done
  fi
}

function index_apt_deployed() {
  local p2repoPathComplete=$1
  if [ ! -d $1 ]; then
    echo "The parameter $1 is required to be a valid folder"
  fi
  cd $p2repoPathComplete
  #we are here: $groupID/$branchName/$buildID and there is: debs
  #in the deployment directory.
  packages_rel_dir=$(basename `pwd`)/debs
  cd ..
  packages_rel_dir=$(basename `pwd`)/$packages_rel_dir
  cd ..
  if [ -d "$packages_rel_dir" ]; then
    echo "apt-ftparchive packages $packages_rel_dir > $packages_rel_dir/Packages in "`pwd`
    apt-ftparchive packages $packages_rel_dir > $packages_rel_dir/Packages
  fi
  cd $WORKSPACE_MODULE_FOLDER
}


#Copy the p2 repositories to their destination folders
function copy_p2_repositories() {
  [ -z "$find_built_p2_repositories_was_called" ] && find_built_p2_repositories
  [ -z "$populate_built_p2_repositories_with_debs_was_called" ] && populate_built_p2_repositories_with_debs

  echo "Deploying ${#built_p2_repositories[*]} repositories"

  existing_repos=()
  for built_repository in ${built_p2_repositories[*]}; do
    p2repoPathComplete=`compute_p2_repository_deployment_folder $built_repository | tail -n 1`
    p2repoPath=${p2repoPathComplete%/*}
    echo "p2repoPathComplete $p2repoPathComplete"
    echo "$built_repository deployed in $p2repoPathComplete"
    #let's make sure we don't have already a repository folder:
    for existing_repo in ${existing_repos[*]}; do
      if [ "$existing_repo" = "$p2repoPathComplete" ]; then
        echo "FATAL: There are at least 2 repositories generated in this project in the folder $existing_repo."
        echo "It is required that all but one of the pom.xml where a repository is produced define:"
        echo " <properties><repositorySuffix>a_unique_suffix</repositorySuffix></properties>"
        echo "Or to replace the last token of the groupId by another one define "
        echo " <properties><repositoryOverrideSuffix>a_unique_suffix</repositoryOverrideSuffix></properties>"
        exit 128
      fi
    done 

    existing_repos[${#existing_repos[*]}]=$p2repoPathComplete

    if [ -n "$BASE_FILE_PATH_P2_REPO" ]; then
#      if [ -d "$p2repoPathComplete" ]; then
#        echo "Warn: Removing the existing repository $p2repoPathComplete"
#        rm -rf $p2repoPathComplete
#      fi
#      mkdir -p $p2repoPathComplete
      echo "Deploying $built_repository/* in $p2repoPathComplete"
      #cp -r $built_repository/* $p2repoPathComplete
      ssh ${REMOTE_USER}@${REMOTE_VM} "cd $p2repoPath; rm -rf $completeVersion; mkdir $completeVersion"
      scp -r $built_repository/* ${REMOTE_USER}@${REMOTE_VM}:${p2repoPathComplete}
      #must make sure we create the symlink in the right folder to have rsync find it later.
      ssh ${REMOTE_USER}@${REMOTE_VM} "cd $p2repoPath; rm -rf $SYM_LINK_CURRENT_NAME; ln -sf $completeVersion $SYM_LINK_CURRENT_NAME"
      #index_apt_deployed $p2repoPathComplete

      #Deploy the 'latest' version of the composite repository
      if [ -d "target/repository_latest" ]; then
        write_p2_index `pwd`"/target/repository_latest"
        #[ -d "$p2repoPath/latest" ] && rm -rf "$p2repoPath/latest"
        #mkdir -p $p2repoPath/latest
        #cp -r target/repository_latest/* $p2repoPath/latest
        ssh ${REMOTE_USER}@${REMOTE_VM} "cd $p2repoPath; rm -rf latest; mkdir latest"
        scp -r target/repository_latest/* ${REMOTE_USER}@${REMOTE_VM}:$p2repoPath/latest
	#index_apt_deployed $p2repoPath/latest
      fi

    else
      echo "Warn: the constant BASE_FILE_PATH_P2_REPO is not defined so no deploym,ent is actually taking place."
    fi


  done
  if [ -z "${existing_repos[0]}" ]; then
    echo "No repositories to deploy ${built_p2_repositories[0]}"
  fi
}

if [ -z "$ROOT_POM" ]; then
  if [ -f "Buildfile" -a -d "target/repository" ]; then
    echo "A buildr build: no p2 repository built by tycho to deploy. Let's look for a composite repository that was built"
    find_built_p2_repositories
    populate_built_p2_repositories_with_debs
    copy_p2_repositories
  else
    echo "Not a tycho build and not a composite repo build"
  fi
else
  create_ius_and_debs_array
  find_built_p2_repositories
  populate_built_p2_repositories_with_debs
  copy_p2_repositories
  ### Create a report of repositories used during this build.
  set +e
  $SCRIPTPATH/tycho/tycho-resolve-p2repo-versions.rb --pom $WORKSPACE_MODULE_FOLDER/pom.xml
  repo_report="pom.repositories_report.xml"
  set -e
fi
