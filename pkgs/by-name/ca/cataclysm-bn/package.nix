{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  gettext,
  sdl3-shadercross,
  sdl3,
  sdl3-image,
  sdl3-mixer,
  sdl3-ttf,
  ncurses,
  sqlite,
  zlib,
  tiles ? true,
  useXdgDir ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cataclysm-bn";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "cataclysmbn";
    repo = "Cataclysm-BN";
    tag = "v${finalAttrs.version}";
    hash = "sha256-LDwkj/47Q3Bru4YCyVz/w2yJbst4DxBKOyXMVEvjRHM=";
  };

  postPatch = ''
    # Upstream derives the version from git, which is unavailable in the sandbox
    substitute src/version.h.in src/version.h \
      --subst-var-by VERSION ${finalAttrs.version}
    echo "${finalAttrs.version}" > VERSION.txt

    # Look for translation files where they are installed (see cmakeFlags)
    substituteInPlace src/language.cpp \
      --replace-fail 'PATH_INFO::base_path() + "lang/mo/"' \
                     'PATH_INFO::base_path() + "share/cataclysm-bn/lang/mo/"'

    # Fonts are resolved relative to PATH_INFO::fontdir()
    substituteInPlace data/raw/fonts.json \
      --replace-fail 'data/font/' ""
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    gettext
    sdl3-shadercross
  ];

  # SDL3 is required for both the tiles and curses builds
  buildInputs = [
    sdl3
    sqlite
    zlib
  ]
  ++ lib.optionals tiles [
    sdl3-image
    sdl3-mixer
    sdl3-ttf
  ]
  ++ lib.optional (!tiles) ncurses;

  cmakeFlags = [
    (lib.cmakeBool "TILES" tiles)
    (lib.cmakeBool "CURSES" (!tiles))
    (lib.cmakeBool "SOUND" tiles)
    (lib.cmakeBool "USE_XDG_DIR" useXdgDir)
    (lib.cmakeBool "USE_HOME_DIR" (!useXdgDir))
    (lib.cmakeBool "TESTS" false)
    (lib.cmakeBool "LUA_DOCS_ON_BUILD" false)
    (lib.cmakeBool "CATA_CCACHE" false)
    (lib.cmakeBool "CATA_FORMAT_TARGETS" false)
    (lib.cmakeBool "BUILD_SHADERCROSS" false)
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
    (lib.cmakeFeature "CMAKE_INSTALL_LOCALEDIR" "share/cataclysm-bn/lang")
  ];

  postInstall = lib.optionalString tiles ''
    install -Dm644 ../data/XDG/org.cataclysmbn.CataclysmBN.desktop \
      -t $out/share/applications
    install -Dm644 ../data/XDG/org.cataclysmbn.CataclysmBN.svg \
      -t $out/share/icons/hicolor/scalable/apps
    install -Dm644 ../data/XDG/org.cataclysmbn.CataclysmBN.metainfo.xml \
      -t $out/share/metainfo
  '';

  enableParallelBuilding = true;

  meta = {
    description = "Post-apocalyptic roguelike, fork of Cataclysm: Dark Days Ahead";
    longDescription = ''
      Cataclysm: Bright Nights is a roguelike with sci-fi elements set in a
      post-apocalyptic world. It is a fork of Cataclysm: Dark Days Ahead that
      focuses on gameplay over realism, and adds Lua modding support.
    '';
    homepage = "https://docs.cataclysmbn.org/";
    changelog = "https://github.com/cataclysmbn/Cataclysm-BN/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      cc-by-sa-30
      # Magical Nights mod
      cc-by-sa-40
      # Terminus font
      ofl
    ];
    maintainers = with lib.maintainers; [ pltrz ];
    mainProgram = if tiles then "cataclysm-bn-tiles" else "cataclysm-bn";
    # Upstream expects precompiled shaders on Darwin, which are not in the source tree
    platforms = lib.platforms.linux;
  };
})
