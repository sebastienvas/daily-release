#!/bin/bash

# Copyright 2017 Istio Authors

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

# Exit immediately for non zero status
set -e
# Check unset variables
set -u
# Print commands
set -x


function cleanup() {
  # log gathering
  cp -a /tmp/istio* ${ARTIFACTS_DIR}
  # Mason cleanup
  mason_cleanup
  cat "${FILE_LOG}"
}

source greenBuild.VERSION

# Check https://github.com/istio/test-infra/blob/master/boskos/configs.yaml
# for existing resources types
RESOURCE_TYPE="${RESOURCE_TYPE:-gke-e2e-test}"
OWNER='e2e-daily'
INFO_PATH="$(mktemp /tmp/XXXXX.boskos.info)"
FILE_LOG="$(mktemp /tmp/XXXXX.boskos.log)"

# Artifact dir is hardcoded in Prow - boostrap to be in first repo checked out
ARTIFACTS_DIR="${GOPATH}/src/github.com/istio-releases/daily-release/_artifacts"

# Exports $HUB, $TAG, and $ISTIOCTL_URL
ISTIOCTL_STAGE_URL=${ISTIOCTL_URL}-stage
echo "Using artifacts from HUB=${HUB} TAG=${TAG} ISTIOCTL_STAGE_URL=${ISTIOCTL_STAGE_URL}"

ISTIO_SHA=`curl $ISTIOCTL_URL/../manifest.xml | grep -E "name=\"(([a-z]|-)*)/istio\"" | cut -f 6 -d \"`
[[ -z "${ISTIO_SHA}"  ]] && echo "error need to test with specific SHA" && exit 1

# Checkout istio at the greenbuild
mkdir -p ${GOPATH}/src/istio.io
pushd ${GOPATH}/src/istio.io
git clone -n https://github.com/istio/istio.git
pushd istio
git checkout $ISTIO_SHA

source "prow/mason_lib.sh"
source "prow/cluster_lib.sh"

# Download envoy and go deps
make init

trap cleanup EXIT

# use uploaded yaml artifacts rather than the ones generated locally
DAILY_BUILD=istio-$(echo ${ISTIOCTL_URL} | cut -d '/' -f 6)
LINUX_DIST_URL=${ISTIOCTL_URL/istioctl/${DAILY_BUILD}-linux.tar.gz}
wget $LINUX_DIST_URL
tar -xzf ${DAILY_BUILD}-linux.tar.gz
cp -R ${DAILY_BUILD}/install/* install/

get_resource "${RESOURCE_TYPE}" "${OWNER}" "${INFO_PATH}" "${FILE_LOG}"
setup_cluster

echo 'Running E2E Tests'
E2E_ARGS=(
  --ca_hub="${HUB}"
  --ca_tag="${TAG}"
  --istioctl_url "${ISTIOCTL_STAGE_URL}"
  --mason_info="${INFO_PATH}"
  --mixer_hub="${HUB}"
  --mixer_tag="${TAG}"
  --pilot_hub="${HUB}"
  --pilot_tag="${TAG}"
  --proxy_hub="${PROXY_HUB:-${HUB}}"
  --proxy_tag="${PROXY_TAG:-${TAG}}"
  --test_logs_path="${ARTIFACTS_DIR}"
)

# The --default_proxy flag overwrites both --proxy_hub  and --proxy_tag
go test -v -timeout 20m ./tests/e2e/tests/simple -args ${E2E_ARGS[@]} "$@"
go test -v -timeout 20m ./tests/e2e/tests/mixer -args ${E2E_ARGS[@]} "$@"
go test -v -timeout 40m ./tests/e2e/tests/bookinfo -args ${E2E_ARGS[@]} "$@"
