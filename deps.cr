#!/usr/bin/env crystal

require "json"

srcdir = Path.posix(__DIR__)
libdir = Path.new(__DIR__, "lib")

Dir.glob(Path.new(srcdir, "src", "bitte_ci", "cli", "*")) do |cmd|
  found = Set(Path).new
  found << Path.posix(cmd)

  paths = Set(Path).new

  Process.run("strace", args: [
    "-e", "trace=%file", "-s", "1000", "-z", "-qqq", "-f", "crystal", "build", cmd,
  ]) do |process|
    process.error.each_line do |line|
      next unless line =~ /"([^"]+\.(?:cr|cue|ecr))"/
      paths << Path.posix($1).expand
    end
  end

  pp! paths

  paths.each do |path|
    parents = path.parents

    next if parents.includes?(libdir)
    next unless parents.includes?(srcdir)

    found << path
  end

  pp! found

  inputs = found.map { |f| f.relative_to(srcdir / "pkgs/bitte-ci") }

  file = %([ #{inputs.sort.join(" ")} ])
  formatted = IO::Memory.new
  Process.run("nixfmt", input: IO::Memory.new(file), output: formatted)

  File.write("pkgs/bitte-ci/input_#{File.basename(cmd, ".cr")}.nix", formatted.to_s)
end
