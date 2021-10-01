#!/usr/bin/env crystal

require "log"

def collect(path, found : Set(Path)) : Nil
  found << path

  File.open(path) do |io|
    io.each_line do |line|
      line.split(",").each do |part|
        case part
        when /"([^"]+\.ecr)"/
          Dir.glob($1.gsub(/\{\{tmpl\.id\}\}/, "*")) { |p| found << Path[p] }
        when /read_file "([^"]+)"/
          found << Path[$1]
        when /^require\s+"(\.[^"]+)"/
          normal = (path.parent/"#{$1}.cr").normalize
          found << normal if File.exists?(normal)
          Dir.glob(normal) { |inner|
            collect(Path[inner], found)
          }
        end
      end
    end
  end

  nil
end

srcdir = Path.posix(__DIR__)

Dir.glob("src/bitte_ci/cli/*.cr") do |cli|
  path = Path[cli]
  Log.info { "Collecting dependencies for #{cli}" }
  found = Set(Path).new
  collect(path, found)

  Log.info { "found #{found.size} files" }

  inputs = found.map { |f| (Path[__DIR__] / f).relative_to(srcdir / "pkgs/bitte-ci") }

  file = %([ #{inputs.sort.join(" ")} ])
  formatted = IO::Memory.new
  Process.run("nixfmt", input: IO::Memory.new(file), output: formatted)

  puts formatted.to_s

  File.write("pkgs/bitte-ci/input_#{File.basename(cli, ".cr")}.nix", formatted.to_s)
end
