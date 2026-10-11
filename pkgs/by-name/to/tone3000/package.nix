{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  gitUpdater,

  # nativeBuildInputs
  cmake,
  copyDesktopItems,
  makeDesktopItem,
  ninja,
  pkg-config,
  writableTmpDirAsHomeHook,

  # buildInputs
  alsa-lib,
  curl,
  fontconfig,
  gtk3,
  libjack2,
  libx11,
  libxcomposite,
  libxcursor,
  libxext,
  libxi,
  libxinerama,
  libxrandr,
  libxrender,

  # OAuth client id the plugin uses to sign in to tone3000.com and browse
  # tones. It is a publishable key meant to be embedded in client code
  # (https://www.tone3000.com/api) and is the same one upstream's prebuilt
  # binaries ship with. Set to "" to build without TONE3000 sign-in; local
  # .nam/IR loading keeps working.
  publishableKey ? "t3k_pub__B8V_QGmV50ov2YWJzjqOxQE0q1-wURs",
}:

let
  # Pinned by the CPMAddPackage calls in CMakeLists.txt and
  # plugin/CMakeLists.txt; bump these together with the plugin.
  cpmVersion = "0.40.2";
  cpm = fetchurl {
    url = "https://github.com/cpm-cmake/CPM.cmake/releases/download/v${cpmVersion}/CPM.cmake";
    hash = "sha256-yM3DLAOBZTjOInge1ylk3IZLKjSjENO3EEgSpcotg10=";
  };

  cpmDeps = {
    JUCE = fetchFromGitHub {
      owner = "juce-framework";
      repo = "JUCE";
      tag = "9.0.3";
      hash = "sha256-eB5HvUiKXRAp53EApiX0jGNhXVtt83zD9TaNOhdQIjc=";
    };
    freetype = fetchFromGitHub {
      owner = "freetype";
      repo = "freetype";
      tag = "VER-2-13-3";
      hash = "sha256-4l90lDtpgm5xlh2m7ifrqNy373DTRTULRkAzicrM93c=";
    };
    GOOGLETEST = fetchFromGitHub {
      owner = "google";
      repo = "googletest";
      tag = "v1.15.2";
      hash = "sha256-1OJ2SeSscRBNr7zZ/a8bJGIqAnhkg45re0j3DtPfcXM=";
    };
    clap-juce-extensions = fetchFromGitHub {
      owner = "free-audio";
      repo = "clap-juce-extensions";
      rev = "c1a5ad025f95d01e03267857fa8276ebeed16500";
      fetchSubmodules = true;
      hash = "sha256-P8rLNI9fXGU8yxXXdOkRD/+T3AMd3zdRM8mHp62dEmA=";
    };
  };

  # Directory names under libs/ that the CPMAddPackage SOURCE_DIRs point at.
  libDirs = {
    JUCE = "juce";
    freetype = "freetype";
    GOOGLETEST = "googletest";
    clap-juce-extensions = "clap-juce-extensions";
  };

  # JUCE dlopens these at runtime instead of linking them.
  runtimeLibs = [
    curl
    libjack2
    libx11
    libxcursor
    libxext
    libxinerama
    libxrandr
  ];

  artefacts = "plugin/TONE3000_artefacts/Release";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "tone3000";
  version = "0.0.12";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "tone-3000";
    repo = "tone3000-plugin";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-eqytMDN727rAUFCWkr1eSYpPwTdjtgPKpl1iusL/oWs=";
  };

  # The root CMakeLists.txt patches JUCE in place under libs/ at configure
  # time (and silently skips the patches if libs/juce is missing), so the CPM
  # dependencies are copied into the writable source tree rather than pointed
  # at in the store.
  postUnpack = ''
    mkdir -p $sourceRoot/libs/cpm
    cp ${cpm} $sourceRoot/libs/cpm/CPM_${cpmVersion}.cmake
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (name: src: ''
      cp -r ${src} $sourceRoot/libs/${libDirs.${name}}
    '') cpmDeps
  )
  + ''
    chmod -R u+w $sourceRoot/libs
  '';

  postPatch = ''
    substituteInPlace plugin/src/PresetManager.cpp \
      --replace-fail '"/usr/share/TONE3000/Presets/Factory"' "\"$out/share/TONE3000/Presets/Factory\""
  '';

  nativeBuildInputs = [
    cmake
    copyDesktopItems
    ninja
    pkg-config
    writableTmpDirAsHomeHook
  ];

  buildInputs = [
    alsa-lib
    curl
    fontconfig
    gtk3
    libjack2
    libx11
    libxcomposite
    libxcursor
    libxext
    libxi
    libxinerama
    libxrandr
    libxrender
  ];

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_TOOLCHAIN_FILE" "cmake/linux-toolchain.cmake")
    (lib.cmakeBool "BUILD_AAX" false)
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
  ];

  preConfigure = lib.concatStrings (
    lib.mapAttrsToList (name: _: ''
      appendToVar cmakeFlags "-DCPM_${name}_SOURCE=$PWD/libs/${libDirs.${name}}"
    '') cpmDeps
  );

  env.T3K_PUBLISHABLE_KEY = publishableKey;

  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkPhase = ''
    runHook preCheck
    ctest --test-dir test --output-on-failure
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 ${artefacts}/Standalone/TONE3000 -t $out/bin
    install -Dm755 ${artefacts}/CLAP/TONE3000.clap -t $out/lib/clap
    mkdir -p $out/lib/{vst3,lv2}
    cp -r ${artefacts}/VST3/TONE3000.vst3 $out/lib/vst3/
    cp -r ${artefacts}/LV2/TONE3000.lv2 $out/lib/lv2/

    install -Dm644 ../resources/factory-presets/*.t3kpreset -t $out/share/TONE3000/Presets/Factory
    install -Dm644 ../script/installer/linux/tone3000.png $out/share/icons/hicolor/512x512/apps/tone3000.png

    runHook postInstall
  '';

  # The plugins are loaded into hosts whose library path we don't control, so
  # every binary needs the dlopened libraries on its own rpath.
  postFixup = ''
    for f in $out/bin/TONE3000 $out/lib/clap/TONE3000.clap \
      $out/lib/vst3/TONE3000.vst3/Contents/*/TONE3000.so \
      $out/lib/lv2/TONE3000.lv2/*.so; do
      patchelf --add-rpath ${lib.makeLibraryPath runtimeLibs} "$f"
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "tone3000";
      desktopName = "TONE3000";
      comment = "Play NAM captures and IRs straight from TONE3000";
      exec = "TONE3000";
      icon = "tone3000";
      categories = [
        "AudioVideo"
        "Audio"
        "Music"
      ];
      startupWMClass = "TONE3000";
    })
  ];

  passthru.updateScript = gitUpdater { rev-prefix = "v"; };

  meta = {
    description = "Neural Amp Modeler and IR loader plugin with access to the TONE3000 library";
    homepage = "https://www.tone3000.com/plugin";
    changelog = "https://github.com/tone-3000/tone3000-plugin/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "TONE3000";
    maintainers = with lib.maintainers; [ pltrz ];
    platforms = lib.platforms.linux;
  };
})
