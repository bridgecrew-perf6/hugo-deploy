#!/bin/bash

# Environment variables:
#
#   DEPLOY_KEY          SSH private key (required)
#
#   DEPLOY_REPO         GitHub Pages repository (default: current)
#   DEPLOY_BRANCH       GitHub Pages publishing branch (default: gh-pages)
#   DEPLOY_DEST_DIR     GitHub Pages publishing folder (default: root folder)
#
#   GITHUB_ACTOR        GitHub username (automatic)
#   GITHUB_REPOSITORY   GitHub repository (source code) (automatic)
#   GITHUB_WORKSPACE    GitHub workspace (automatic)
#
#   TZ                  Timezone (default: UTC)
#
#   HUGO_VERSION        Version of hugo (default: latest)
#   HUGO_EXTENDED       Extended version of hugo (default: true)
#   HUGO_BUILD_PARAMS   Hugo build parameters (default: "--gc --minify")

set -e

: ${DEPLOY_REPO:="${GITHUB_REPOSITORY}"}
: ${DEPLOY_BRANCH:="gh-pages"}
: ${TZ:="UTC"}
: ${HUGO_VERSION:="latest"}
: ${HUGO_BUILD_PARAMS:="--gc --minify"}
: ${DEPLOY_DEST_DIR:="/"}

GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

git config --global user.name "${GITHUB_ACTOR}"
git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"

git config --global core.quotePath false
ln -s /usr/share/zoneinfo/${TZ} /etc/localtime

if [[ "${DEPLOY_REPO}" != "${GITHUB_REPOSITORY}" ]]; then
  mkdir /root/.ssh
  ssh-keyscan -t rsa github.com > /root/.ssh/known_hosts && \
  echo "${DEPLOY_KEY}" > /root/.ssh/id_rsa && \
  chmod 400 /root/.ssh/id_rsa
fi

if [[ "${HUGO_VERSION}" == "latest" ]]; then
  HUGO_VERSION=$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/gohugoio/hugo/releases/latest | sed -nr 's/^.*\/v([^\/])/\1/gp')
fi

HUGO_EXTENDED_STR=""
if [[ "${HUGO_EXTENDED}" != "0" && "${HUGO_EXTENDED}" != "false" ]]; then
  HUGO_EXTENDED_STR="_extended"
fi


pushd /usr/bin

curl -q -Ls "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo${HUGO_EXTENDED_STR}_${HUGO_VERSION}_Linux-64bit.tar.gz" -o - | tar -xzvf - hugo

popd

git config --global --add safe.directory "${GITHUB_WORKSPACE}"
cd "${GITHUB_WORKSPACE}"

SITE_SOURCE_DIR=$(mktemp -d -t sitesource-XXXXX -p "${PWD}")
PUBLISH_DIR=$(mktemp -d -t hugopub-XXXXX -p "${PWD}")
SITE_DST_REPO_DIR=$(mktemp -d -t site-dst-repo-XXXXX -p "${PWD}")
SITE_DST_REPO_TARGET_BACKUP_DIR=$(mktemp -u -d -t site-dst-repo-tb-XXXXX -p "${PWD}")

git clone --recurse-submodules "git@github.com:${GITHUB_REPOSITORY}.git" --branch "${GITHUB_REF_NAME}" --single-branch "${SITE_SOURCE_DIR}" && cd "${SITE_SOURCE_DIR}"


if ! hugo --gc --minify --destination "${PUBLISH_DIR}"; then
   exit 1
fi

git clone --recurse-submodules "git@github.com:${DEPLOY_REPO}.git" --branch "${DEPLOY_BRANCH}" "${SITE_DST_REPO_DIR}" && cd "${SITE_DST_REPO_DIR}"

mv "./${DEPLOY_DEST_DIR}" "${SITE_DST_REPO_TARGET_BACKUP_DIR}" || true
mv "${PUBLISH_DIR}" "./${DEPLOY_DEST_DIR}"

set -x 

if [[ -f "${SITE_SOURCE_DIR}/keep_files.txt" ]]; then
  pushd "${SITE_DST_REPO_DIR}/${DEPLOY_DEST_DIR}"
  FF_CMD='xargs realpath -e -q --relative-base="." | grep -vE "^\/"'
  cat "${SITE_SOURCE_DIR}/keep_files.txt" | eval "${FF_CMD}" | xargs rm -rf 
  cd "${SITE_DST_REPO_TARGET_BACKUP_DIR}/."
  cat "${SITE_SOURCE_DIR}/keep_files.txt" | eval "${FF_CMD}" | xargs cp -a --parents -t "${SITE_DST_REPO_DIR}/${DEPLOY_DEST_DIR}"
  popd
fi

git add --all
git commit -m "Automated deployment @ $(date '+%Y-%m-%d %H:%M:%S') ${TZ}"
git push origin "${DEPLOY_BRANCH}"

rm -rf /root/.ssh
