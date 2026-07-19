{
  lib,
  stdenv,
  odin,
  clang,
  patchelf,
  makeWrapper,
  version,
  src,
}:

stdenv.mkDerivation {
  pname = "ren-tui";
  inherit version src;

  nativeBuildInputs = [
    odin
    clang
    patchelf
    makeWrapper
  ];

  # Vendored glibc librns. Musl builds are not supported for runtime packages.
  dontPatchELF = false;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export ODIN_ROOT=${odin}/share
    make all LIBC=glibc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install PREFIX=$out DESTDIR= LIBC=glibc
    install -Dm644 LICENSE $out/share/doc/ren-tui/LICENSE
    install -Dm644 README.md $out/share/doc/ren-tui/README.md
    install -Dm644 CHANGELOG.md $out/share/doc/ren-tui/CHANGELOG.md
    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal LXMF / NomadNet client for Reticulum";
    homepage = "https://github.com/Quad4-Software/Ren-TUI";
    license = licenses.bsd0;
    platforms = platforms.linux;
    mainProgram = "ren-tui";
  };
}
