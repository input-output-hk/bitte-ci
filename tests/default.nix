{ lib, pkgs, ... }:
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
    ${pkgs.bitte-ci}/bin/bitte-ci --queue --githubusercontent-url http://127.0.0.1:8080 < ${pr}
  '';

  testFlake = pkgs.writeText "flake.nix" ''
    {
      description = "Test";
      outputs = { self }: {
        packages.x86_64-linux.hello = builtins.toFile "hello" "hello";
      };
    }
  '';

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

    server = WEBrick::HTTPServer.new(Port: 9090)
    trap('INT') { server.shutdown }
    server.mount_proc "/" do |req, res|
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

        environment.systemPackages = with pkgs; [ curl ];

        systemd.services.fakeGithub = {
          description = "Fake GitHub";
          before = ["bitte-ci-server.service"];
          wantedBy = ["multi-user.target"];
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

            git config --global init.defaultBranch master
            git config --global user.email "test@example.com"
            git config --global user.name "Test"
            git init
            cp ${ciCue} ci.cue
            cp ${testFlake} flake.nix
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
            dbUrl = "postgres://bitte_ci@localhost:5432/bitte_ci";
            githubusercontentUrl = "http://localhost:8080";
          };

          nomad = {
            enable = true;
            settings = {
              server = {
                enabled = true;
                bootstrap_expect = 1;
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

      ci.log(ci.succeed("${testJob}"))
      ci.sleep(60)
    '';
  };
}
