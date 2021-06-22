{ stdenv, fetchzip }:
stdenv.mkDerivation {
  pname = "ngrok";
  version = "stable";

  src = fetchzip {
    url = "https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip";
    hash = "sha256-ZlWcnyaF087gJ17d1KDMm+xvLJi9wIGV7VP8ya+W9KM=";
  };

  buildPhase = ":";

  installPhase = ''
    mkdir -p $out/bin
    cp $src/ngrok $out/bin/ngrok
    chmod +x $out/bin/ngrok
  '';
}
