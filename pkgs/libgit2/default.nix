{ lib, stdenv, fetchFromGitHub, cmake, pkg-config, python3, zlib, libssh2
, openssl, pcre, libiconv, Security }:

stdenv.mkDerivation rec {
  pname = "libgit2";
  version = "1.1.1";
  # keep the version in sync with python3.pkgs.pygit2 and libgit2-glib

  src = fetchFromGitHub {
    owner = "libgit2";
    repo = "libgit2";
    rev = "v${version}";
    sha256 = "sha256-SxceIxT0aeiiiZCeSIe6EOa+MyVpQVaiv/ZZn6fkwIc=";
  };

  cmakeFlags = [ "-DTHREADSAFE=ON" ];

  nativeBuildInputs = [ cmake python3 pkg-config ];

  buildInputs = [ zlib libssh2 openssl pcre ]
    ++ lib.optional stdenv.isDarwin Security;

  propagatedBuildInputs = lib.optional (!stdenv.isLinux) libiconv;

  doCheck = false; # hangs. or very expensive?

  meta = {
    description = "The Git linkable library";
    homepage = "https://libgit2.github.com/";
    license = lib.licenses.gpl2;
    platforms = with lib.platforms; all;
  };
}
