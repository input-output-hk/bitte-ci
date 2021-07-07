job "bitte-ci" {
  datacenters = ["dc1"]
  type        = "batch"

  group "@@GROUP_NAME@@" {
    task "runner" {
      driver = "exec"

      leader = true

      config {
        flake = "github:NixOS/nixpkgs/nixos-21.05#hello"
        command = "/bin/bash"
        args = ["/local/runner.sh"]
      }

      template {
        destination = "/local/runner.sh"
        perms = "777"
        data = <<-EOH
        set -exuo pipefail

        dir="/local/$FULL_NAME"

        if [ ! -d "$dir" ]; then
          mkdir -p "$(dirname "$dir")"

          git clone "$CLONE_URL" "$dir"
          git -C "$dir" checkout "$SHA"
        fi

        cd "$dir"

        "$COMMAND"

        # Ensure logs are flushed
        sleep 10
        EOH
      }

      template {
        destination = "/local/payload.json"
        perms = "600"
        data = <<-EOH
        @@PAYLOAD@@
        EOH
      }

      env = {
        PATH = "/bin"
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt"
        SHA = "@@pull_request.head.sha@@"
        CLONE_URL = "@@pull_request.head.repo.clone_url@@"
        LABEL = "@@pull_request.head.label@@"
        REF = "@@pull_request.head.ref@@"
        FULL_NAME = "@@pull_request.head.repo.full_name@@"
        COMMAND = "@@COMMAND@@"
      }
    }

    task "promtail" {
      driver = "exec"

      config {
        flake = "github:NixOS/nixpkgs/nixos-21.05#grafana-loki"
        command = "/bin/promtail"
        args = ["-config.file", "local/config.yaml"]
      }

      template {
        destination = "/local/config.yaml"
        data = <<-EOH
        server:
          http_listen_port: 0
          grpc_listen_port: 0
        positions:
          filename: /local/positions.yaml
        client:
          url: http://127.0.0.1:3100/loki/api/v1/push
        scrape_configs:
        - job_name: 'leader-2-0'
          pipeline_stages: null
          static_configs:
          - labels:
              nomad_alloc_id: '{{ env "NOMAD_ALLOC_ID" }}'
              nomad_alloc_index: '{{ env "NOMAD_ALLOC_INDEX" }}'
              nomad_alloc_name: '{{ env "NOMAD_ALLOC_NAME" }}'
              nomad_dc: '{{ env "NOMAD_DC" }}'
              nomad_group_name: '{{ env "NOMAD_GROUP_NAME" }}'
              nomad_job_id: '{{ env "NOMAD_JOB_ID" }}'
              nomad_job_name: '{{ env "NOMAD_JOB_NAME" }}'
              nomad_job_parent_id: '{{ env "NOMAD_JOB_PARENT_ID" }}'
              nomad_namespace: '{{ env "NOMAD_NAMESPACE" }}'
              nomad_region: '{{ env "NOMAD_REGION" }}'
              bitte_ci_id: '@@BITTE_CI_ID@@'
              __path__: /alloc/logs/*.std*.[0-9]*
        EOH
      }
    }
  }
}
