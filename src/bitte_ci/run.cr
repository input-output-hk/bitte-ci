require "json"

module BitteCI
  module Runner
    def self.queue(template, pr)
      loki_id = UUID.random
      full_name = pr["pull_request"]["base"]["repo"]["full_name"]
      number = pr["pull_request"]["number"].as_i64
      sha = pr["pull_request"]["head"]["sha"]

      group_name = "#{full_name}##{number}:#{sha}"

      hcl = template
        .gsub("@@PAYLOAD@@", pr.to_json)
        .gsub("@@GROUP_NAME@@", group_name)
        .gsub("@@BITTE_CI_ID@@", loki_id)
        .gsub("@@FLAKE@@", ".#bitte-ci-env")
        .gsub(/@@([^@]+)@@/) do |match|
          path = $1.split('.')
          path.reduce(pr) { |s, v| s[v] }
        end

      tempfile = File.tempfile(".hcl") do |file|
        file.write hcl.to_slice
      end

      mem = IO::Memory.new
      status = Process.run("nomad", output: mem, args: [
        "job", "run", "-detach", tempfile.path,
      ])

      tempfile.delete

      output = mem.to_s

      unless status.success?
        puts "Running the nomad job has failed with #{status.exit_status}"
        puts output
        exit status.exit_status
      end

      output =~ /Evaluation ID:\s+(.+)/
      eval_id = $1

      DB.open(OPTIONS[:db_url]) do |db|
        db.transaction do
          pr_id = pr["pull_request"]["id"].as_i64
          db.exec <<-SQL, pr_id, pr.to_json
            INSERT INTO pull_requests (id, data) VALUES ($1, $2)
            ON CONFLICT (id) DO UPDATE SET data = $2;
          SQL

          db.exec "SELECT pg_notify($1, $2)", "pull_requests", pr_id

          db.exec <<-SQL, eval_id, pr_id, loki_id, Time.utc, "pending"
            INSERT INTO builds
            (id, pr_id, loki_id, created_at, build_status)
            VALUES
            ($1, $2, $3, $4, $5);
          SQL

          db.exec "SELECT pg_notify($1, $2)", "builds", eval_id
        end
      end
    end
  end
end
