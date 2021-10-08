{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "liftbridge";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "liftbridge-io";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-XPCqH4AQH2wwj8ImyJkPMT4wk7t4JYt+WeohtdmPW8U=";
  };

  vendorSha256 = "sha256-aPKk64w6xBF0GEx7ltQEeNPGNEwE1npM4+FJAmFzPNQ=";

  postPatch = ''
    substituteInPlace server/server_test.go \
      --replace TestTLS SkipTLS

    substituteInPlace server/server_test.go \
      --replace TestPropagatedShrinkExpandISR SkipPropagatedShrinkExpandISR

    substituteInPlace server/config_test.go \
      --replace TestNewConfigNATSTLS SkipNewConfigNATSTLS
  '';

  meta = with lib; {
    description = "Lightweight, fault-tolerant message streams.";
    homepage = "https://liftbridge.io";
    license = licenses.asl20;
    maintainers = with maintainers; [ manveru ];
  };
}

