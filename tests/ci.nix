{ lib, pkgs, inputs, ... }:
let
  repo =
    pkgs.runCommand "repo.sh" { buildInputs = [ pkgs.coreutils pkgs.git ]; } ''
      export HOME=$PWD

      git config --global init.defaultBranch master
      git config --global user.email "test@example.com"
      git config --global user.name "Test"

      mkdir -p $out
      cd $out
      git init
      cp ${./ci.cue} ci.cue
      cp ${./flake.nix} flake.nix
      cp ${../flake.lock} flake.lock
      git add .
      git commit -m 'inaugural commit'
    '';

  rev = builtins.readFile
    (pkgs.runCommand "rev.sh" { buildInputs = [ pkgs.git ]; } ''
      git -C ${repo} log --format=format:%H | head -1 > $out
    '');

  pr = pkgs.writeText "pr.json" (builtins.toJSON {
    pull_request = {
      id = 1;
      number = 1;

      statuses_url = "http://127.0.0.1:9090/github";

      base = {
        repo = {
          full_name = "iog/ci";
          clone_url = "git://127.0.0.1:7070/";
        };
        sha = rev;
        label = "";
        ref = "";
      };

      head = {
        repo = {
          full_name = "iog/ci";
          clone_url = "git://127.0.0.1:7070/";
        };
        sha = rev;
        label = "";
        ref = "";
      };
    };
  });

  githubHookSecretFile =
    builtins.toFile "secret" "oos0kahquaiNaiciz8MaeHohNgaejien";
  githubTokenFile = builtins.toFile "github" "token";
  nomadTokenFile = builtins.toFile "nomad" "secret";
  artifactSecretFile = builtins.toFile "hmac" "something";

  bitteConfig = pkgs.writeText "bitte.json" (builtins.toJSON {
    public_url = "http://127.0.0.1:9494";
    postgres_url = "postgres://bitte_ci@127.0.0.1:5432/bitte_ci";
    github_user_content_base_url = "http://localhost:9090";
    github_hook_secret_file = githubHookSecretFile;
    nomad_base_url = "http://localhost:4646";
    loki_base_url = "http://127.0.0.1:3100";
    github_token_file = githubTokenFile;
    github_user = "tester";
    nomad_token_file = nomadTokenFile;
    nomad_datacenters = [ "dc1" ];
    runner_flake = "path:/bitte-ci";
    artifact_secret_file = artifactSecretFile;
  });

  queueJob = pkgs.writeShellScript "test.sh" ''
    set -exuo pipefail

    export PATH="${lib.makeBinPath [ pkgs.cue ]}:$PATH"
    ${pkgs.bitte-ci.queue}/bin/bitte-ci-queue --config ${bitteConfig} < ${pr}
  '';

  checkJob = pkgs.writeShellScript "check.sh" ''
    sleep 2

    set -exuo pipefail

    nomad status

    status="$(nomad job status iog/ci#1-${rev})"
    echo "vvv STATUS vvv"
    echo "$status"
    id="$(nomad job status iog/ci#1-${rev} | tail -1 | awk '{print $1}')"
    echo "vvv JOB vvv"
    job="$(nomad status "$id")"
    echo "$job"

    systemd-cat bat /var/lib/nomad/alloc/*/*/logs/*

    uuid="$(
      echo '{"channel":"pull_requests"}' \
        | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
        | jq -r '.value[0].builds[0].id'
    )"

    echo '{"channel":"build"}' \
      | jq -c --arg uuid "$uuid" '.uuid = $uuid' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
      | systemd-cat jq

    echo '{"channel":"build"}' \
      | jq -c --arg uuid "$uuid" '.uuid = $uuid' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
      | jq -e -r '.value.logs[][].line' \
      | grep goodbye

    echo '{"channel":"allocation"}' \
      | jq -c --arg uuid "$(echo "$job" | awk '/ID/ { print $3; exit }')" '.uuid = $uuid' \
      | websocat -B 1000000 ws://0.0.0.0:9494/ci/api/v1/socket \
      | jq
  '';

  fakeGithub = pkgs.writeText "github.rb" ''
    require "webrick"
    require "json"

    server = WEBrick::HTTPServer.new(Port: 9090)
    trap('INT') { server.shutdown }

    server.mount_proc "/registry.json" do |req, res|
      res.body = {flakes: []}.to_json
      res.status = 200
    end

    server.mount_proc "/github" do |req, res|
      puts "Received github status request:"
      pp JSON.parse(req.body)
      res.body = "OK"
      res.status = 201
    end

    server.mount_proc "/iog/ci/${rev}/ci.cue" do |req, res|
      puts "Received ci.cue request"
      res.body = File.read("${./ci.cue}")
      res.status = 200
    end

    server.start
  '';

  bitteCiFlake = pkgs.writeShellScript "ci.sh" ''
    cp -r ${inputs.self} /bitte-ci
  '';
in pkgs.nixosTest {
  name = "bitte-ci";

  nodes = {
    ci = {
      imports = [ ../modules/bitte-ci.nix ];

      # Nomad exec driver is incompatible with cgroups v2
      systemd.enableUnifiedCgroupHierarchy = false;
      virtualisation.memorySize = 5 * 1024;
      virtualisation.diskSize = 2 * 1024;
      virtualisation.pathsInNixDB = (builtins.attrValues inputs)
        ++ (with pkgs; [
          bitte-ci.command
          bitte-ci.command-static
          bitte-ci.prepare
          bitte-ci.prepare-static
        ]);

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

      environment.systemPackages = with pkgs; [
        curl
        gawk
        tree
        websocat
        jq
        bat
        git
      ];

      nix = {
        # registry.nixpkgs.flake = inputs.nixpkgs;
        # registry.crystal-src.flake = inputs.crystal-src;

        registry = let m = lib.mapAttrs (name: flake: { inherit flake; });
        in (m inputs) // (m inputs.inclusive.inputs);

        extraOptions = ''
          experimental-features = nix-command flakes ca-references
          show-trace = true
          log-lines = 100
          flake-registry = http://localhost:9090/registry.json
        '';
      };

      systemd.services.fake-github = {
        description = "Fake GitHub";
        before = [ "bitte-ci-server.service" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ ruby ];
        script = ''
          exec ruby ${fakeGithub}
        '';
      };

      systemd.services.git-daemon = {
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ git ];
        environment.HOME = "/root";
        script = ''
          set -exuo pipefail

          exec git daemon \
            --listen=0.0.0.0 \
            --port=7070 \
            --verbose \
            --export-all \
            --base-path=${repo}/.git \
            --reuseaddr \
            --strict-paths ${repo}/.git/
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
          package = pkgs.bitte-ci;
          postgresUrl = "postgres://bitte_ci@localhost:5432/bitte_ci";
          githubUserContentUrl = "http://localhost:9090";
          nomadUrl = "http://localhost:4646";
          publicUrl = "http://127.0.0.1:9494";
          lokiUrl = "http://127.0.0.1:3100";
          githubUser = "tester";
          nomadDatacenters = [ "dc1" ];
          inherit githubTokenFile nomadTokenFile githubHookSecretFile
            artifactSecretFile;
        };

        nomad = {
          enable = true;
          enableDocker = false;
          extraPackages = with pkgs; [ nix git ];

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
              reserved.memory = 512;
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

    ci.wait_for_unit("git-daemon")

    ci.wait_for_unit("fake-github")
    ci.wait_for_open_port(9090)

    # wait for nomad to respond
    ci.wait_for_unit("nomad")
    ci.wait_for_open_port(4646)

    # wait for nomad to be leader
    ci.wait_for_console_text("client: node registration complete")

    ci.wait_for_unit("bitte-ci-migrate")
    ci.wait_for_unit("bitte-ci-migrate")
    ci.wait_for_unit("bitte-ci-server")
    ci.wait_for_unit("bitte-ci-listener")

    # wait for bitte ci server to respond
    ci.wait_for_open_port(9494)

    ci.log(ci.succeed("${bitteCiFlake}"))
    ci.log(ci.succeed("nix build ${repo}#prepare-static"))

    ci.log(ci.succeed("${queueJob}"))

    ci.log(ci.wait_until_succeeds("${checkJob}"))
  '';
}
