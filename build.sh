#!/usr/bin/env bash

# build script for letsencrypt-sophosutm-dns

set -e
set -u
set -o pipefail
[[ -n "${ZSH_VERSION:-}" ]] && set -o SH_WORD_SPLIT && set +o FUNCTION_ARGZERO

umask 077

# Find directory in which this script is stored by traversing all symbolic links
SOURCE="${0}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

BASEDIR="${SCRIPTDIR}"
BUILDDIR="build"
DISTDIR="dist"
SRCDIR="src"
CHECKSUM="checksum.md5"

PROJNAME="leutmdns"

_exiterr() {
  echo "ERROR: ${1}" >&2
  exit 1
}

command_clean() {
  [[ ! -d ${BASEDIR}/${BUILDDIR} ]] || rm -r ${BASEDIR}/${BUILDDIR} || _exiterr "Unable to clean ${BASEDIR}/${BUILDDIR} directory."
  [[ ! -d ${BASEDIR}/${PROJNAME} ]] || rm -r ${BASEDIR}/${PROJNAME} || _exiterror "Unable to clean ${BASEDIR}/${PROJNAME} directory."
}

command_build() {
  command_clean

  git submodule update --init --recursive

  mkdir -p ${BASEDIR}/${BUILDDIR}/{accounts,certs,refs,tsig} || _exiterr "Unable to create ${BASEDIR}/${BUILDDIR} directory."
  cp -t ${BASEDIR}/${BUILDDIR}/ ${BASEDIR}/dehydrated/dehydrated ${BASEDIR}/dehydrated/docs/examples/{config,domains.txt} ${BASEDIR}/utm-update-certificate/utm_update_certificate.pl || _exiterr "An error occured copying submodule files.  Make sure you run the command 'git submodule update --init --recursive' before building."
  cp -t ${BASEDIR}/${BUILDDIR}/ ${BASEDIR}/${SRCDIR}/{hook.sh,openssl.cnf} || _exiterr "An error occured copying src files."

  # Create the package
  [[ -d ${BASEDIR}/${DISTDIR} ]] || mkdir -p ${BASEDIR}/${DISTDIR} || _exiterr "Unable to create ${BASEDIR}/${DISTDIR} directry."
  [[ ! -f ${BASEDIR}/${DISTDIR}/${PROJNAME}.tar.gz ]] || rm ${BASEDIR}/${DISTDIR}/${PROJNAME}.tar.gz
  [[ ! -f ${BASEDIR}/${DISTDIR}/${CHECKSUM} ]] || rm ${BASEDIR}/${DISTDIR}/${CHECKSUM}
  printf "Creating distribution package: ${PROJNAME}.tar.gz\nLocation: ${BASEDIR}/${DISTDIR}/"
  tar -czvf ${BASEDIR}/${DISTDIR}/${PROJNAME}.tar.gz -C ${BASEDIR} --transform "s/^${BUILDDIR}/${PROJNAME}/" ${BUILDDIR}
  md5sum ${BASEDIR}/${DISTDIR}/${PROJNAME}.tar.gz > ${BASEDIR}/${DISTDIR}/${CHECKSUM}
  command_clean
}

main() {
  COMMAND=""
  set_command() {
    [[ -z "${COMMAND}" ]] || _exiterr "Only one command can be executed at a time.  See help for more information."
    COMMAND="${1}"
  }

  while (( ${#} )); do
    case "${1}" in
      build|-b)
        set_command build
        ;;

      clean|-c)
        set_command clean
        ;;

      *)
        set_command build
        ;;
      esac

      shift 1
    done

    case "${COMMAND}" in
      clean) echo "Cleaning build."; command_clean;;
      *) command_build;;
  esac
}

main "${@:-}"
