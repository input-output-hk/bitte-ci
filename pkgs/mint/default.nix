{ lib, fetchFromGitHub, crystal, openssl, pkg-config }:
crystal.buildCrystalPackage rec {
  version = "0.13.1";
  pname = "mint";
  format = "shards";

  src = fetchFromGitHub {
    owner = "mint-lang";
    repo = "mint";
    rev = version;
    sha256 = "sha256-friq7DfTnXyW7TpAZX6rsi5QAinYj/RIdMdr4Ee44rw=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # Update with
  #   wget https://github.com/mint-lang/mint/blob/0.13.1/shard.lock
  #   nix-shell -p crystal2nix --run crystal2nix
  #   rm shard.lock
  shardsFile = ./shards.nix;
  crystalBinaries.mint.src = "src/mint.cr";

  meta = {
    description = "A refreshing language for the front-end web";
    homepage = https://mint-lang.com/;
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ manveru ];
    platforms = [ "x86_64-linux" "i686-linux" "x86_64-darwin" ];
  };
}
