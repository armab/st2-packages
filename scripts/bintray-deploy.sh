#!/bin/bash

# API-related Constants
API=https://api.bintray.com
NOT_FOUND=404
SUCCESS=200
CREATED=201

# Project-related Constants
VCS_URL=https://github.com/stackstorm/st2.git
DEBIAN_DISTRIBUTION=wheezy,trusty
DEBIAN_COMPONENT=main

# Pass these ENV Variables
# BINTRAY_ACCOUNT - your BinTray username
# BINTRAY_API_KEY - act as a password for REST authentication

# Arguments
# $1 BINTRAY_REPO - the targeted repo
# $2 PKG_DIR - directory with packages

function main() {
  BINTRAY_REPO=$1
  PKG_DIR=$2

  : ${BINTRAY_ACCOUNT:? BINTRAY_ACCOUNT env is required}
  : ${BINTRAY_ACCOUNT:? BINTRAY_API_KEY env is required}

  : ${BINTRAY_REPO:? repo (first arg) is required}
  : ${PKG_DIR:? dir (second arg) is required}

  if [ ! -d "$PKG_DIR" ]; then
    echo "No directory $PKG_DIR, aborting..."
    exit 1
  fi

  for PKG_PATH in ${PKG_DIR}/*.{deb,rpm}; do

    PKG=`basename ${PKG_PATH}`
    # Parse metadata from package file name `st2api_0.14dev-20_amd64.deb`
    # st2api
    PKG_NAME=${PKG%%_*}
    # 0.14dev
    PKG_VERSION=$(echo ${PKG} | awk -F_ '{print $2}' | awk -F- '{print $1}')
    # 20
    PKG_RELEASE=$(echo ${PKG} | awk -F_ '{print $2}' | awk -F- '{print $2}')
    # amd64
    PKG_ARCH=$(echo ${PKG##*_} | awk -F. '{print $1}')
    # deb
    PKG_TYPE=${PKG##*.}
    #

    if [ -z "$PKG_NAME" ] || [ -z "$PKG_VERSION" ] || [ -z "$PKG_RELEASE" ]; then
     echo "$PKG_PATH doesn't look like package, skipping..."
     continue
    fi

    echo "[DEBUG] BINTRAY_ACCOUNT:  ${BINTRAY_ACCOUNT}"
    echo "[DEBUG] BINTRAY_REPO:     ${BINTRAY_REPO}"
    echo "[DEBUG] PKG_PATH:         ${PKG_PATH}"
    echo "[DEBUG] PKG:              ${PKG}"
    echo "[DEBUG] PKG_NAME:         ${PKG_NAME}"
    echo "[DEBUG] PKG_VERSION:      ${PKG_VERSION}"
    echo "[DEBUG] PKG_RELEASE:      ${PKG_RELEASE}"
    echo "[DEBUG] PKG_ARCH:         ${PKG_ARCH}"
    echo "[DEBUG] PKG_TYPE:         ${PKG_TYPE}"

    init_curl
    if (! check_package_exists); then
      echo "[DEBUG] The package ${PKG_NAME} does not exit. It will be created"
      exit 1
      create_package
    fi

    deploy_${PKG_TYPE}
  done
}

function init_curl() {
  CURL="curl -u${BINTRAY_ACCOUNT}:${BINTRAY_API_KEY} -H Content-Type:application/json -H Accept:application/json"
}

function check_package_exists() {
  echo "[DEBUG] Checking if package ${PKG_NAME} exists..."
  [ $(${CURL} --write-out %{http_code} --silent --output /dev/null -X GET ${API}/packages/${BINTRAY_ACCOUNT}/${BINTRAY_REPO}/${PKG_NAME}) -eq ${SUCCESS} ]
  package_exists=$?
  echo "[DEBUG] Package ${PKG_NAME} exists? y:0/N:1 (${package_exists})"
  return ${package_exists}
}

function create_package() {
  echo "[DEBUG] Creating package ${PKG_NAME}..."
  data="{
  \"name\": \"${PKG_NAME}\",
  \"desc\": \"\",
  \"vcs_url\": \"${VCS_URL}\",
  \"licenses\": [\"Apache-2.0\"]
  }"

  ${CURL} -X POST -d "${data}" ${API}/packages/${BINTRAY_ACCOUNT}/${BINTRAY_REPO}/
}

function upload_content() {
  echo "[DEBUG] Uploading ${PKG_PATH}..."
  [ $(${CURL} --write-out %{http_code} --silent --output /dev/null -T ${PKG_PATH} -H X-Bintray-Package:${PKG_NAME} -H X-Bintray-Version:${PKG_VERSION}-${PKG_RELEASE} -H X-Bintray-Debian-Distribution:${DEBIAN_DISTRIBUTION} -H X-Bintray-Debian-Component:${DEBIAN_COMPONENT} -H X-Bintray-Debian-Architecture:${PKG_ARCH} ${API}/content/${BINTRAY_ACCOUNT}/${BINTRAY_REPO}/${PKG}) -eq ${CREATED} ]
  uploaded=$?
  echo "[DEBUG] DEB ${PKG_PATH} uploaded? y:0/N:1 (${uploaded})"
  return ${uploaded}
}

function deploy_deb() {
  if (upload_content); then
    echo "[DEBUG] Publishing ${PKG_PATH}..."
    ${CURL} -X POST ${API}/content/${BINTRAY_ACCOUNT}/${BINTRAY_REPO}/${PKG_NAME}/${PKG_VERSION}-${PKG_RELEASE}/publish -d "{ \"discard\": \"false\" }"
  else
    echo "[SEVERE] First you should upload your deb ${PKG_PATH}"
    exit 2
  fi
}

function deploy_rpm() {
  echo "[DEBUG] Unsupported"
  exit 0
}

main "$@"
