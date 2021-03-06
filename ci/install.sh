#!/usr/bin/env bash
set -exu

. ci/utils.inc.sh

mkdir -p "$LOCAL_BUILDS"

function install_botan() {
  # botan
  botan_build=${LOCAL_BUILDS}/botan
  if [ ! -e "${BOTAN_INSTALL}/lib/libbotan-2.so" ] && \
     [ ! -e "${BOTAN_INSTALL}/lib/libbotan-2.dylib" ] && \
     [ ! -e "${BOTAN_INSTALL}/lib/libbotan-2.a" ]; then

    if [ -d "${botan_build}" ]; then
      rm -rf "${botan_build}"
    fi

    git clone --depth 1 --branch 2.17.3 https://github.com/randombit/botan "${botan_build}"
    pushd "${botan_build}"

    osparam=
    if [ $(get_os) == "msys" ]; then
      osparam="--os=mingw"
    fi

    cpuparam=
    [ -z "$CPU" ] || cpuparam="--cpu=$CPU --disable-cc-tests"

    ./configure.py --prefix="${BOTAN_INSTALL}" --with-debug-info --cxxflags="-fno-omit-frame-pointer" \
      $osparam $cpuparam --without-documentation --without-openssl --build-targets=shared \
      --minimized-build --enable-modules="$BOTAN_MODULES"
    ${MAKE} -j${MAKE_PARALLEL} install
    popd
  fi
}

install_jsonc() {
  # json-c
  jsonc_build=${LOCAL_BUILDS}/json-c
  if [ ! -e "${JSONC_INSTALL}/lib/libjson-c.so" ] && \
     [ ! -e "${JSONC_INSTALL}/lib/libjson-c.dylib" ] && \
     [ ! -e "${JSONC_INSTALL}/lib/libjson-c.a" ]; then

     if [ -d "${jsonc_build}" ]; then
       rm -rf "${jsonc_build}"
     fi

    mkdir -p "${jsonc_build}"
    pushd ${jsonc_build}
    wget https://s3.amazonaws.com/json-c_releases/releases/json-c-0.12.1.tar.gz -O json-c.tar.gz
    tar xzf json-c.tar.gz --strip 1

    autoreconf -ivf
    cpuparam=
    [ -z "$CPU" ] || cpuparam="--build=$CPU"
    env CFLAGS="-fno-omit-frame-pointer -Wno-implicit-fallthrough -g" ./configure $cpuparam --prefix="${JSONC_INSTALL}"
    ${MAKE} -j${MAKE_PARALLEL} install
    popd
  fi
}

_install_gpg() {
  local VERSION_SWITCH=$1
  local NPTH_VERSION=$2
  local LIBGPG_ERROR_VERSION=$3
  local LIBGCRYPT_VERSION=$4
  local LIBASSUAN_VERSION=$5
  local LIBKSBA_VERSION=$6
  local PINENTRY_VERSION=$7
  local GNUPG_VERSION=$8

  gpg_build="$PWD"
  gpg_install="$GPG_INSTALL"
  mkdir -p "$gpg_build" "${gpg_install}"
  git clone --depth 1 https://github.com/rnpgp/gpg-build-scripts
  pushd gpg-build-scripts
  cpuparam=
  [ -z "$CPU" ] || cpuparam="--build=$CPU"
  configure_opts="\
      --prefix=${gpg_install} \
      --with-libgpg-error-prefix=${gpg_install} \
      --with-libassuan-prefix=${gpg_install} \
      --with-libgcrypt-prefix=${gpg_install} \
      --with-ksba-prefix=${gpg_install} \
      --with-npth-prefix=${gpg_install} \
      --disable-doc \
      --enable-pinentry-curses \
      --disable-pinentry-emacs \
      --disable-pinentry-gtk2 \
      --disable-pinentry-gnome3 \
      --disable-pinentry-qt \
      --disable-pinentry-qt4 \
      --disable-pinentry-qt5 \
      --disable-pinentry-tqt \
      --disable-pinentry-fltk \
      --enable-maintainer-mode \
      $cpuparam"
  common_args=(
      --build-dir "$gpg_build" \
      --configure-opts "$configure_opts"
  )

  # Workaround to correctly build pinentry on the latest GHA on macOS. Most likely there is a better solution.
  export CFLAGS="-D_XOPEN_SOURCE_EXTENDED"
  export CXXFLAGS="-D_XOPEN_SOURCE_EXTENDED"

  for component in libgpg-error:$LIBGPG_ERROR_VERSION \
                   libgcrypt:$LIBGCRYPT_VERSION \
                   libassuan:$LIBASSUAN_VERSION \
                   libksba:$LIBKSBA_VERSION \
                   npth:$NPTH_VERSION \
                   pinentry:$PINENTRY_VERSION \
                   gnupg:$GNUPG_VERSION; do
    name="${component%:*}"
    version="${component#*:}"
    bash -x ./install_gpg_component.sh \
      --component-name "$name" \
      --$VERSION_SWITCH "$version" \
      "${common_args[@]}"
  done
  popd
}


install_gpg() {
  # gpg - for msys/windows we use shipped gpg2 version
  gpg_build=${LOCAL_BUILDS}/gpg
  if [ ! -e "${GPG_INSTALL}/bin/gpg" ]; then
    mkdir -p "${gpg_build}"
    pushd "${gpg_build}"

    if [ "$GPG_VERSION" = "stable" ]; then
      #                              npth libgpg-error libgcrypt libassuan libksba pinentry gnupg
      _install_gpg component-version 1.6  1.39         1.8.7     2.5.4     1.5.0   1.1.0    2.2.24
    elif [ "$GPG_VERSION" = "beta" ]; then
      #                              npth    libgpg-error libgcrypt libassuan libksba pinentry gnupg
      _install_gpg component-git-ref 2501a48 f73605e      d9c4183   909133b   3df0cd3 0e2e53c  c6702d7
    else
      echo "\$GPG_VERSION is set to invalid value: $GPG_VERSION"
      exit 1
    fi
    popd
  fi
}

install_bundler() {
  # ruby-rnp
  which bundle || ${SUDO_GEM} install bundler
}

install_asciidoc() {
  which asciidoctor || ${SUDO_GEM} install asciidoctor
}

if ([ "$(get_os)" = "linux" ] && [ "$(get_linux_dist)" = "centos" ]); then
  SUDO_GEM="gem"
else
  SUDO_GEM="${SUDO} gem"
fi
default=(botan jsonc gpg bundler asciidoc)
items=("${@:-${default[@]}}")
for item in "${items[@]}"; do
  install_"$item"
done
