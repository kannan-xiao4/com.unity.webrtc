@echo off

if not exist depot_tools (
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
)

set COMMAND_DIR=%~dp0
set PATH=%cd%\depot_tools;%PATH%
set WEBRTC_VERSION=6998
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
set PYTHONIOENCODING=utf-8
set GYP_GENERATORS=ninja,msvs-ninja
set GYP_MSVS_VERSION=2022
set OUTPUT_DIR=out
set ARTIFACTS_DIR=%cd%\artifacts
set vs2022_install=C:\Program Files\Microsoft Visual Studio\2022\Community

@REM if not exist src (
@REM   call fetch.bat --nohooks webrtc
@REM   cd src
@REM   call git.bat config --system core.longpaths true
@REM   call git.bat checkout  refs/remotes/branch-heads/%WEBRTC_VERSION%
@REM   cd ..
@REM   call gclient.bat sync -D --force --reset
@REM ) else (
@REM   call gclient.bat sync --with_branch_heads --with_tags
@REM   cd src
@REM   call git.bat fetch -p
@REM   call git.bat checkout  refs/remotes/branch-heads/%WEBRTC_VERSION%
@REM   cd ..
@REM   call gclient.bat sync -D --force --reset
@REM )

rem add jsoncpp
patch -N "src\BUILD.gn" < "%COMMAND_DIR%\patches\add_jsoncpp.patch"

@REM rem fix towupper
@REM patch -N "src\modules\desktop_capture\win\full_screen_win_application_handler.cc" < "%COMMAND_DIR%\patches\fix_towupper.patch"

@REM rem fix abseil
@REM patch -N "src\third_party\abseil-cpp/absl/base/config.h" < "%COMMAND_DIR%\patches\fix_abseil.patch"

@REM rem fix task_queue_base
@REM patch -N "src\api\task_queue\task_queue_base.h" < "%COMMAND_DIR%\patches\fix_task_queue_base.patch"

@REM rem fix SetRawImagePlanes() in LibvpxVp8Encoder
@REM patch -N "src\modules\video_coding\codecs\vp8\libvpx_vp8_encoder.cc" < "%COMMAND_DIR%\patches\libvpx_vp8_encoder.patch"

mkdir "%ARTIFACTS_DIR%\lib"

setlocal enabledelayedexpansion

for %%i in (x64) do (
  mkdir "%ARTIFACTS_DIR%/lib/%%i"
  for %%j in (true false) do (
    set outputDir="!OUTPUT_DIR!_%%i_%%j"

    rem generate ninja for release
    call gn.bat gen "!outputDir!" --root="src" ^
      --args="is_debug=%%j target_os=\"win\" target_cpu=\"%%i\" rtc_build_tools=false rtc_build_examples=false rtc_include_tests=false rtc_use_h264=false rtc_use_perfetto=false use_custom_libcxx=false use_rtti=true libyuv_include_tests=false"

    rem build
    call ninja.bat -C !outputDir! webrtc

    set filename=
    if true==%%j (
      set filename=webrtcd.lib
    ) else (
      set filename=webrtc.lib
    )

    rem copy static library for release build
    copy "!outputDir!\obj\webrtc.lib" "%ARTIFACTS_DIR%\lib\%%i\!filename!"
  )
)

rem generate license
call python.bat "%cd%\src\tools_webrtc\libs\generate_licenses.py" ^
  --target :webrtc !outputDir! !outputDir!

rem unescape license
powershell -ExecutionPolicy RemoteSigned -File "%COMMAND_DIR%\Unescape.ps1" "!outputDir!\LICENSE.md"

rem copy header
xcopy src\*.h "%ARTIFACTS_DIR%\include" /C /S /I /F /H

rem copy inc file about abseil-cpp (need inc)
xcopy src\third_party\abseil-cpp\*.inc "%ARTIFACTS_DIR%\include" /C /S /I /F /H

rem copy license
copy "!outputDir!\LICENSE.md" "%ARTIFACTS_DIR%"

endlocal

@REM rem create zip
@REM cd %ARTIFACTS_DIR%
@REM 7z a -tzip webrtc-win.zip *