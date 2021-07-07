{ lib, pkgs, inputs, ... }:
let
  pr = pkgs.writeText "pr.json" (builtins.toJSON {
    pull_request = {
      id = 1;
      number = 1;

      statuses_url = "http://127.0.0.1:9090/";

      base = {
        repo = {
          full_name = "";
          clone_url = "";
        };
        sha = "";
        label = "";
        ref = "";
      };

      head = {
        repo = {
          full_name = "";
          clone_url = "";
        };
        sha = "";
        label = "";
        ref = "";
      };
    };
  });

  testJob = pkgs.writeShellScript "test.sh" ''
    ${pkgs.bitte-ci}/bin/bitte-ci queue \
      --github-user-content-base-url http://127.0.0.1:8080 \
      --public-url http://example.com \
      --postgres-url "postgres://bitte_ci@localhost:5432/bitte_ci" \
      --github-user-content-base-url "http://localhost:8080" \
      --nomad-base-url "http://localhost:4646" \
      --public-url "http://example.com" \
      --loki-base-url "http://localhost:3100" \
      --nomad-token foobar \
      --github-hook-secret "oos0kahquaiNaiciz8MaeHohNgaejien" \
      --github-user "tester" \
      --github-token "token" \
      --frontend-path ${pkgs.bitte-ci-frontend} \
      < ${pr}

    free -h

    nomad node status
    id="$(nomad node status | tail -1 | awk '{print $1}')"
    nomad node status "$id"

    nomad job status
  '';

  testFlake = pkgs.writeText "flake.nix" ''
    {
      description = "Test";
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
      };
      outputs = { self, nixpkgs }:
        let pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in {
          packages.x86_64-linux = {
            grafana-loki = pkgs.grafana-loki;
            hello = pkgs.hello;
          };
        };
    }
  '';

  testFlakeLock = pkgs.writeText "flake.lock" (builtins.toJSON {
    nodes = {
      nixpkgs = {
        locked = {
          lastModified = 1623961232;
          narHash = "sha256-5X5v37GTBFdQnc3rvbSPJyAtO+/z1wHZF3Kz61g2Mx4=";
          owner = "NixOS";
          repo = "nixpkgs";
          rev = "bad3ccd099ebe9a8aa017bda8500ab02787d90aa";
          type = "github";
        };
        original = {
          owner = "NixOS";
          ref = "nixos-21.05";
          repo = "nixpkgs";
          type = "github";
        };
      };
      root = { inputs = { nixpkgs = "nixpkgs"; }; };
    };
    root = "root";
    version = 7;
  });

  ciCue = pkgs.writeText "ci.cue" ''
    package ci

    ci: steps: [
      {
        label: "hello"
        command: "hello"
        flake: "path:/test-repo#hello"
      }
    ]
  '';

  fakeGithub = pkgs.writeText "github.rb" ''
    require "webrick"
    require "json"

    # ${inputs.self.legacyPackages.x86_64-linux.grafana-loki}
    # ${inputs.self.legacyPackages.x86_64-linux.hello}

    server = WEBrick::HTTPServer.new(Port: 9090)
    trap('INT') { server.shutdown }

    server.mount_proc "/registry.json" do |req, res|
      puts "Received registry request: #{req.inspect}"
      res.body = {flakes: []}.to_json
      res.status = 200
    end

    server.mount_proc "/github" do |req, res|
      puts "Received github status request: #{req.inspect}"
      res.body = "OK"
      res.status = 201
    end

    server.start
  '';
in {
  test-bitte-ci = pkgs.nixosTest {
    name = "bitte-ci";

    nodes = {
      ci = {
        imports = [ ../modules/bitte-ci.nix ];

        # Nomad exec driver is incompatible with cgroups v2
        systemd.enableUnifiedCgroupHierarchy = false;
        virtualisation.memorySize = 3 * 1024;
        virtualisation.diskSize = 2 * 1024;

        environment.systemPackages = with pkgs; [ curl gawk ];

        nix = {
          package = pkgs.nixFlakes;
          registry.nixpkgs.flake = inputs.nixpkgs;
          extraOptions = ''
            experimental-features = nix-command flakes ca-references
            show-trace = true
            log-lines = 100
            flake-registry = http://localhost:9090/registry.json
          '';
        };

        systemd.services.fakeGithub = {
          description = "Fake GitHub";
          before = [ "bitte-ci-server.service" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ ruby ];
          script = ''
            exec ruby ${fakeGithub}
          '';
        };

        systemd.services.webfsd = {
          before = [ "bitte-ci-server.service" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ webfs git ];
          environment = { HOME = "/root"; };
          script = ''
            set -exuo pipefail

            mkdir -p /test-repo
            cd /test-repo

            ln -s ${builtins.getFlake "github:NixOS/nixpkgs?rev=aea7242187f21a120fe73b5099c4167e12ec9aab"} nomad-nixpkgs

            git config --global init.defaultBranch master
            git config --global user.email "test@example.com"
            git config --global user.name "Test"
            git init
            cp ${ciCue} ci.cue
            cp ${testFlake} flake.nix
            cp ${testFlakeLock} flake.lock
            git add .
            git commit -m 'inaugural commit'

            exec webfsd -F -j -p 8080 -r /test-repo
          '';
        };

        services = {
          postgresql = {
            enable = true;
            enableTCPIP = true;

            authentication = ''
              host all all localhost trust
              host all all 127.0.0.1/32 trust
            '';

            initialScript = pkgs.writeText "init.sql" ''
              CREATE DATABASE bitte_ci;
              CREATE USER bitte_ci;
              GRANT ALL PRIVILEGES ON DATABASE bitte_ci to bitte_ci;
              ALTER USER bitte_ci WITH SUPERUSER;
            '';
          };

          bitte-ci = {
            enable = true;
            postgresUrl = "postgres://bitte_ci@localhost:5432/bitte_ci";
            githubUserContentUrl = "http://localhost:8080";
            nomadUrl = "http://localhost:4646";
            publicUrl = "http://example.com";
            lokiUrl = "http://localhost:3100";
            githubHookSecretFile =
              builtins.toFile "secret" "oos0kahquaiNaiciz8MaeHohNgaejien";
            githubUser = "tester";
            githubTokenFile = builtins.toFile "github" "token";
            nomadTokenFile = builtins.toFile "nomad" "secret";
          };

          nomad = {
            enable = true;
            enableDocker = false;
            extraPackages = with pkgs; [ nixFlakes ];

            # required for exec driver
            dropPrivileges = false;

            settings = {
              log_level = "DEBUG";
              datacenter = "dc1";
              server = {
                enabled = true;
                bootstrap_expect = 1;
              };

              client = {
                enabled = true;
                reserved.memory = 256;
              };
            };
          };

          loki = {
            enable = true;
            configuration = {
              auth_enabled = false;
              ingester = {
                chunk_idle_period = "5m";
                chunk_retain_period = "30s";
                lifecycler = {
                  address = "127.0.0.1";
                  final_sleep = "0s";
                  ring = {
                    kvstore = { store = "inmemory"; };
                    replication_factor = 1;
                  };
                };
              };
              limits_config = {
                enforce_metric_name = false;
                ingestion_burst_size_mb = 160;
                ingestion_rate_mb = 160;
                reject_old_samples = true;
                reject_old_samples_max_age = "168h";
              };
              schema_config = {
                configs = [{
                  from = "2020-05-15";
                  index = {
                    period = "168h";
                    prefix = "index_";
                  };
                  object_store = "filesystem";
                  schema = "v11";
                  store = "boltdb";
                }];
              };
              server = { http_listen_port = 3100; };
              storage_config = {
                boltdb = { directory = "/var/lib/loki/index"; };
                filesystem = { directory = "/var/lib/loki/chunks"; };
              };
              table_manager = {
                retention_deletes_enabled = true;
                retention_period = "350d";
              };
            };
          };
        };
      };
    };

    testScript = ''
      start_all()

      # wait for nomad to respond
      ci.wait_for_open_port(4646)

      ci.wait_for_unit("bitte-ci-migrate")
      ci.wait_for_unit("bitte-ci-server")
      ci.wait_for_unit("bitte-ci-listener")

      # wait for the server to respond
      ci.wait_for_open_port(9494)

      # wait for webfs server to respond
      ci.wait_for_open_port(8080)
      ci.wait_for_open_port(9090)

      ci.sleep(10)
      ci.log(ci.succeed("${testJob}"))
      ci.sleep(10)
      ci.log(ci.succeed("nomad status bitte-ci"))
      ci.sleep(60)
    '';
  };
}
