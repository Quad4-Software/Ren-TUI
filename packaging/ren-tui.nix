{
  lib,
  stdenv,
  fetchFromGitHub,
  odin,
  clang,
  patchelf,
  makeWrapper,
  go,
  git,
  gcc,
  version,
  src,
  rnsRef ? "v1.1.0",
}:

let
  reticulum-go = fetchFromGitHub {
    owner = "Quad4-Software";
    repo = "Reticulum-Go";
    rev = rnsRef;
    hash = "sha256-FTh4ruhTrZOEiarj0QBi0+iupwzSE8Mkj6L2UQFs7Zo=";
  };
in
stdenv.mkDerivation {
  pname = "ren-tui";
  inherit version src;

  nativeBuildInputs = [
    odin
    clang
    patchelf
    makeWrapper
    go
    git
    gcc
  ];

  # librns is built from Reticulum-Go at rnsRef (not shipped in src).
  dontPatchELF = false;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export ODIN_ROOT=${odin}/share
    export GOPATH=$TMPDIR/go
    mkdir -p $TMPDIR/rns
    cp -a ${reticulum-go}/. $TMPDIR/rns/
    chmod -R u+w $TMPDIR/rns
    (
      cd $TMPDIR/rns
      CGO_ENABLED=1 go build -mod=vendor -buildmode=c-shared -o bin/librns.so ./cmd/librns
      cp -f include/rns.h bin/rns.h
    )
    make vendor-librns RNS_ROOT=$TMPDIR/rns
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
