#!/bin/bash -eu

if [ ! -e "$(pwd)/depot_tools" ]
then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

export COMMAND_DIR=$(cd $(dirname $0); pwd)
export PATH="$(pwd)/depot_tools:$(pwd)/depot_tools/python-bin:$PATH"
export WEBRTC_VERSION=6367
export OUTPUT_DIR="$(pwd)/out"
export ARTIFACTS_DIR="$(pwd)/artifacts"
export PYTHON3_BIN="$(pwd)/depot_tools/python-bin/python3"

if [ ! -e "$(pwd)/src" ]
then
  fetch --nohooks webrtc
  cd src
  sudo sh -c 'echo 127.0.1.1 $(hostname) >> /etc/hosts'
  sudo git config --system core.longpaths true
  git checkout "refs/remotes/branch-heads/$WEBRTC_VERSION"
  cd ..
  gclient sync -D --force --reset
else
  # fetch and init config on only first time
  cd src
  git checkout "refs/remotes/branch-heads/$WEBRTC_VERSION"
  cd ..
  gclient sync -D --force --reset
fi

# add jsoncpp
patch -N "src/BUILD.gn" < "$COMMAND_DIR/patches/add_jsoncpp.patch"

# Fix SetRawImagePlanes() in LibvpxVp8Encoder
patch -N "src/modules/video_coding/codecs/vp8/libvpx_vp8_encoder.cc" < "$COMMAND_DIR/patches/libvpx_vp8_encoder.patch"

mkdir -p "$ARTIFACTS_DIR/lib"

outputDir=""

for target_cpu in "x64"
do
  mkdir -p "$ARTIFACTS_DIR/lib/${target_cpu}"
  for is_debug in "true" "false"
  do
    outputDir="${OUTPUT_DIR}_${is_debug}_${target_cpu}"
    # use_custom_libcxx=false is failed because install sysroot does not supoort c++11
    args="is_debug=${is_debug} \
      enable_iterator_debugging=false \
      is_component_build=false \
      rtc_include_tests=false \
      rtc_build_examples=false \
      rtc_use_h264=false \
      rtc_use_x11=false \
      symbol_level=0 \
      target_os=\"linux\" \
      target_cpu=\"${target_cpu}\" \
      use_custom_libcxx=true \
      use_rtti=true"

    if [ $is_debug = "true" ]; then
      args="${args} is_asan=true is_lsan=true";
    fi

    # generate ninja files
    gn gen "$outputDir" --root="src" --args="${args}"

    # build static library
    ninja -C "$outputDir" webrtc

    filename="libwebrtc.a"
    if [ $is_debug = "true" ]; then
      filename="libwebrtcd.a"
    fi

    # cppy static library
    cp "$outputDir/obj/libwebrtc.a" "$ARTIFACTS_DIR/lib/${target_cpu}/${filename}"
  done
done

$PYTHON3_BIN "./src/tools_webrtc/libs/generate_licenses.py" \
  --target :webrtc "$outputDir" "$outputDir"

cd src
find . -name "*.h" -print | cpio -pd "$ARTIFACTS_DIR/include"

cp "$outputDir/LICENSE.md" "$ARTIFACTS_DIR"

# create zip
cd "$ARTIFACTS_DIR"
zip -r webrtc-linux.zip lib include LICENSE.md