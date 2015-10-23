#!/bin/bash
#
# Whole package life-cycle entrypoint.
# build -> install -> configure -> test
#

set -e
set -o pipefail

. $(dirname ${BASH_SOURCE[0]})/pipeline.sh

# Build pipeline environment
#
DEBUG="${DEBUG:-0}"

ST2_PACKAGES="st2common st2actions st2api st2auth st2client st2reactor st2exporter st2debug"
ST2_GITURL="${ST2_GITURL:-https://github.com/StackStorm/st2}"
ST2_GITREV="${ST2_GITREV:-master}"
ST2_TESTMODE="${ST2_TESTMODE:-components}"
ST2_WAITFORSTART="${ST2_WAITFORSTART:-10}"

# Create st2python package for outdated OSes (ex. centos6)
ST2_PYTHON="${ST2_PYTHON:-0}"
ST2_PYTHON_VERSION="${ST2_PYTHON_VERSION:-2.7.10}"
ST2_PYTHON_RELEASE="${ST2_PYTHON_RELEASE:-1}"

MISTRAL_ENABLED="${MISTRAL_ENABLED:-1}"
MISTRAL_GITURL="${MISTRAL_GITURL:-https://github.com/StackStorm/mistral}"
MISTRAL_GITREV="${MISTRAL_GITREV:-st2-0.13.1}"

RABBITMQHOST="$(hosts_resolve_ip ${RABBITMQHOST:-rabbitmq})"
MONGODBHOST="$(hosts_resolve_ip ${MONGODBHOST:-mongodb})"
POSTGRESHOST="$(hosts_resolve_ip ${POSTGRESHOST:-postgres})"


# --- Go!
pipe_env DEBUG COMPOSE WAITFORSTART MONGODBHOST RABBITMQHOST POSTGRESHOST \
         ST2_PYTHON ST2_PYTHON_VERSION ST2_PYTHON_RELEASE \
         MISTRAL_ENABLED ARTIFACTS_PATH="/root/build$(mktemp -ud -p /)"

print_details
setup_busybee_sshenv

buildhost_addr="$(hosts_resolve_ip $BUILDHOST)"
ssh_copy scripts $buildhost_addr:

# Create and install python package onto the build host
#
build_st2python
install_st2python

# Invoke st2* components build
if [ ! -z "$BUILDHOST" ] && [ "$ST2_BUILDLIST" != " " ]; then
  build_list="$(components_list)"

  pipe_env  GITURL=$ST2_GITURL GITREV=$ST2_GITREV GITDIR=$(mktemp -ud) \
            MAKE_PRERUN=changelog \
            ST2PKG_VERSION ST2PKG_RELEASE
  debug "Remote environment >>>" "`pipe_env`"

  checkout_repo
  ssh_copy st2/* $buildhost_addr:$GITDIR
  ssh_copy rpmspec $buildhost_addr:$GITDIR
  build_packages "$build_list"
  TESTLIST="$build_list"
else
  # should be given, when run against an already built list
  TESTLIST="$(components_list)"
fi

# We need to choose bundle or common!
TESTLIST="$(cleanup_testlist $TESTLIST)"

# Invoke mistral package build
if [ ! -z "$BUILDHOST" ] && [ "$MISTRAL_ENABLED" = 1 ]; then
  pipe_env  GITURL=$MISTRAL_GITURL GITREV=$MISTRAL_GITREV GITDIR=$(mktemp -ud) \
            MISTRAL_VERSION MISTRAL_RELEASE MAKE_PRERUN=populate_version
  debug "Remote environment >>>" "`pipe_env`"

  checkout_repo
  ssh_copy mistral/* $buildhost_addr:$GITDIR
  ssh_copy rpmspec $buildhost_addr:$GITDIR
  build_packages mistral
  TESTLIST="$TESTLIST mistral"
elif [ "$MISTRAL_ENABLED" = 1 ]; then
  # no build but test, can be when packages are already prebuilt...
  TESTLIST="$TESTLIST mistral"
fi

# Integration loop, test over different platforms
msg_info "\n..... ST2 test mode is \`$ST2_TESTMODE'"
debug "Remote environment >>>" "`pipe_env`"

for host in $TESTHOSTS; do
  testhost_setup $host
  if [ "$ST2_PYTHON" = 1 ]; then
    install_packages $host st2python
  fi
  install_packages $host $TESTLIST
  post_install_setup $host $TESTLIST
  run_rspec $host
done
