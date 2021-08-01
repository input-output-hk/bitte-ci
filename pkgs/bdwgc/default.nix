{ stdenv, fetchpatch, libatomic_ops, src }:
stdenv.mkDerivation rec {
  pname = "boehm-gc";
  version = "8.0.4";

  inherit src;

  patches = [
    (fetchpatch {
      url =
        "https://github.com/ivmai/bdwgc/commit/5668de71107022a316ee967162bc16c10754b9ce.patch";
      sha256 = "02f0rlxl4fsqk1xiq0pabkhwydnmyiqdik2llygkc6ixhxbii8xw";
    })
  ];

  postUnpack = ''
    cp -r ${libatomic_ops} "$sourceRoot/libatomic_ops"
    chmod u+w -R "$sourceRoot/libatomic_ops"
  '';

  configureFlags = [
    "--disable-debug"
    "--disable-dependency-tracking"
    "--disable-shared"
    "--enable-large-config"
  ];

  enableParallelBuilding = true;
}
