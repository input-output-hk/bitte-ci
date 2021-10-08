{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "liftbridge-cli";
  version = "unstable";

  src = fetchFromGitHub {
    owner = "liftbridge-io";
    repo = pname;
    rev = "3f1b33d075149ec86b352f9aa6056cfab2988bcd";
    hash = "sha256-8rp/Wb8VKFd791alA+5aJYX7e5n5w7m4JZR6Y6lhO7A=";
  };

  vendorSha256 = "sha256-3OGLtoMirggJGcutX+howBUYE/cbiZrqCsgan+K+cW8=";

  meta = with lib; {
    description = "Lightweight, fault-tolerant message streams.";
    homepage = "https://liftbridge.io";
    license = licenses.asl20;
    maintainers = with maintainers; [ manveru ];
  };
}

