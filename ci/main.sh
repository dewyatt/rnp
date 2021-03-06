#!/usr/bin/env bash
set -eux

. ci/utils.inc.sh

: "${RNP_TESTS=${RNP_TESTS-.*}}"
: "${LD_LIBRARY_PATH:=}"

build_and_install_cmake() {
  # cmake
  cmake_build=${LOCAL_BUILDS}/cmake
  mkdir -p "${cmake_build}"
  pushd ${cmake_build}
  wget https://github.com/Kitware/CMake/releases/download/v3.19.6/cmake-3.19.6.tar.gz -O cmake.tar.gz
  tar xzf cmake.tar.gz --strip 1
  ./configure --prefix=/usr && ${MAKE} -j${MAKE_PARALLEL} && ${SUDO} make install
  popd
  CMAKE=/usr/bin/cmake
}

build_and_install_python() {
  # python
  python_build=${LOCAL_BUILDS}/python
  mkdir -p "${python_build}"
  pushd ${python_build}
  curl -L -o python.tar.xz https://www.python.org/ftp/python/3.9.2/Python-3.9.2.tar.xz
  tar -xf python.tar.xz --strip 1
  ./configure --enable-optimizations --prefix=/usr && ${MAKE} -j${MAKE_PARALLEL} && ${SUDO} make install
  ${SUDO} ln -sf /usr/bin/python3 /usr/bin/python
  popd
}

CMAKE=cmake

if [[ "$(get_os)" = "linux" ]]; then
  if [[ ${CPU} = "i386" ]]; then
    build_and_install_cmake
    # build_and_install_python
  else
    pushd /
    ${SUDO} curl -L -o cmake.sh https://github.com/Kitware/CMake/releases/download/v3.14.5/cmake-3.14.5-Linux-x86_64.sh
    ${SUDO} sh cmake.sh --skip-license --prefix=/usr
    popd
    CMAKE=/usr/bin/cmake
  fi
fi

cmakeopts=(
  "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
  "-DBUILD_SHARED_LIBS=yes"
  "-DCMAKE_INSTALL_PREFIX=${RNP_INSTALL}"
  "-DCMAKE_PREFIX_PATH=${BOTAN_INSTALL};${JSONC_INSTALL};${GPG_INSTALL}"
)
[ "$BUILD_MODE" = "coverage" ] && cmakeopts+=("-DENABLE_COVERAGE=yes")
[ "$BUILD_MODE" = "sanitize" ] && cmakeopts+=("-DENABLE_SANITIZERS=yes")
[ -v "GTEST_SOURCES" ] && cmakeopts+=("-DGTEST_SOURCES=$GTEST_SOURCES")
[ -v "DOWNLOAD_GTEST" ] && cmakeopts+=("-DDOWNLOAD_GTEST=$DOWNLOAD_GTEST")
[ -v "DOWNLOAD_RUBYRNP" ] && cmakeopts+=("-DDOWNLOAD_RUBYRNP=$DOWNLOAD_RUBYRNP")

if [[ "$(get_os)" = "msys" ]]; then
  cmakeopts+=("-G" "MSYS Makefiles")
fi

mkdir -p "${LOCAL_BUILDS}/rnp-build"
rnpsrc="$PWD"
pushd "${LOCAL_BUILDS}/rnp-build"
export LD_LIBRARY_PATH="${GPG_INSTALL}/lib:${BOTAN_INSTALL}/lib:${JSONC_INSTALL}/lib:${RNP_INSTALL}/lib:$LD_LIBRARY_PATH"

# update dll search path for windows
if [[ "$(get_os)" = "msys" ]]; then
  export PATH="${LOCAL_BUILDS}/rnp-build/lib:${LOCAL_BUILDS}/rnp-build/bin:${LOCAL_BUILDS}/rnp-build/src/lib:$PATH"
fi

${CMAKE} "${cmakeopts[@]}" "$rnpsrc"
make -j${MAKE_PARALLEL} VERBOSE=1 install

: "${COVERITY_SCAN_BRANCH:=0}"
[[ ${COVERITY_SCAN_BRANCH} = 1 ]] && exit 0

# workaround macOS SIP
if [ "$(get_os)" != "msys" ] && \
   [ "$BUILD_MODE" != "sanitize" ] && \
   [ "$(get_os)" = "macos" ]; then
  pushd "$RUBY_RNP_INSTALL"
  cp "${RNP_INSTALL}/lib"/librnp* /usr/local/lib
  popd
fi

#  use test costs to prioritize
mkdir -p "${LOCAL_BUILDS}/rnp-build/Testing/Temporary"
cp "${rnpsrc}/cmake/CTestCostData.txt" "${LOCAL_BUILDS}/rnp-build/Testing/Temporary"

ctest -j"${CTEST_PARALLEL}" -R "$RNP_TESTS" --output-on-failure
popd

exit 0

