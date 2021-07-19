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

  bitteConfig = pkgs.writeText "bitte.json" (builtins.toJSON {
    public_url = "http://example.com";
    postgres_url = "postgres://bitte_ci@localhost:5432/bitte_ci";
    frontend_path = builtins.toString pkgs.bitte-ci-frontend;
    github_user_content_base_url = "http://localhost:8080";
    github_hook_secret_file =
      builtins.toFile "secret" "oos0kahquaiNaiciz8MaeHohNgaejien";
    nomad_base_url = "http://localhost:4646";
    loki_base_url = "http://127.0.0.1:3100";
    github_token_file = builtins.toFile "github" "token";
    github_user = "tester";
    nomad_token_file = builtins.toFile "nomad" "secret";
    nomad_datacenters = "dc1";
    runner_flake = "nixpkgs";
  });

  testJob = pkgs.writeShellScript "test.sh" ''
    set -exuo pipefail

    ${pkgs.bitte-ci}/bin/bitte-ci queue --config ${bitteConfig} < ${pr}
  '';

  checkJob = pkgs.writeShellScript "check.sh" ''
    sleep 2

    status="$(nomad job status bitte-ci)"
    echo "vvv STATUS vvv"
    echo "$status"
    id="$(echo "$status" | nomad job status bitte-ci | tail -1 | awk '{print $1}')"
    echo "vvv JOB vvv"
    nomad status "$id"

    set -x

    echo "vvv LOGS PROMTAIL vvv"
    nomad logs "$id" promtail
    nomad logs -stderr "$id" promtail

    echo "vvv LOGS RUNNER vvv"
    nomad logs "$id" runner
    nomad logs -stderr "$id" runner

    uuid="$(
      echo '{"channel":"pull_requests"}' \
        | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
        | jq -r '.value[0].builds[0].id'
    )"

    json="$(
      echo '{"channel":"build"}' \
        | jq -c --arg uuid "$uuid" '.uuid = $uuid' \
    )"

    echo "$json" \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
      | jq -e '.value.logs[][-1].line == "Hello, world!"'
  '';

  testFlake = pkgs.writeText "flake.nix" ''
    {
      description = "Test";
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
      outputs = { self, nixpkgs }: {
        legacyPackages.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux;
      };
    }
  '';

  testFlakeLock = pkgs.writeText "flake.lock" (builtins.toJSON {
    root = "root";
    version = 7;
    nodes = {
      root.inputs.nixpkgs = "nixpkgs";
      nixpkgs = {
        locked = {
          inherit (inputs.nixpkgs) rev lastModified narHash;
          owner = "NixOS";
          repo = "nixpkgs";
          type = "github";
        };
        original = {
          owner = "NixOS";
          ref = "nixos-21.05";
          repo = "nixpkgs";
          type = "github";
        };
      };
    };
  });

  ciCue = pkgs.writeText "ci.cue" ''
    package ci

    ci: steps: [
      {
        label: "hello"
        command: "hello"
        flakes: "path:/test-repo": ["hello"]
      }
    ]
  '';

  fakeGithub = pkgs.writeText "github.rb" ''
    require "webrick"
    require "json"

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
in pkgs.nixosTest {
  name = "bitte-ci";

  nodes = {
    ci = {
      imports = [ ../modules/bitte-ci.nix ];

      # Nomad exec driver is incompatible with cgroups v2
      systemd.enableUnifiedCgroupHierarchy = false;
      virtualisation.memorySize = 3 * 1024;
      virtualisation.diskSize = 2 * 1024;

      # dependencies required for the ci runner script
      system.extraDependencies = with pkgs; [
        bashInteractive
        cacert
        coreutils
        gnugrep
        git
        hello
        grafana-loki
      ];

      environment.systemPackages = with pkgs; [ curl gawk tree websocat jq ];

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

          ln -s ${
            builtins.getFlake
            "github:NixOS/nixpkgs?rev=aea7242187f21a120fe73b5099c4167e12ec9aab"
          } nomad-nixpkgs

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
          lokiUrl = "http://127.0.0.1:3100";
          githubHookSecretFile =
            builtins.toFile "secret" "oos0kahquaiNaiciz8MaeHohNgaejien";
          githubUser = "tester";
          githubTokenFile = builtins.toFile "github" "token";
          nomadTokenFile = builtins.toFile "nomad" "secret";
          nomadDatacenters = [ "dc1" ];
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
              chroot_env = { "/etc/passwd" = "/etc/passwd"; };
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

    # wait for nomad to be leader
    ci.wait_for_console_text("client: node registration complete")

    ci.wait_for_unit("bitte-ci-migrate")
    ci.wait_for_unit("bitte-ci-server")
    ci.wait_for_unit("bitte-ci-listener")

    # wait for webfs to respond
    ci.wait_for_open_port(8080)
    ci.wait_for_open_port(9090)

    # wait for bitte ci server to respond
    ci.wait_for_open_port(9494)

    ci.log(ci.succeed("${testJob}"))

    ci.log(ci.wait_until_succeeds("${checkJob}"))
  '';
}
