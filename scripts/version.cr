#!/usr/bin/env crystal

require "yaml"

shard = YAML.parse(File.read("shard.yml")).as_h
original = shard["version"].as_s
old = Time.parse(original, "%Y.%m.%d.%L", Time::Location::UTC)

raise "Too many versions today!" if old.millisecond == 999

now = Time.utc
new =
  if old.year == now.year && old.month == now.month && old.day == now.day
    Time.utc(now.year, now.month, now.day) + (1 + old.millisecond).millisecond
  else
    Time.utc(now.year, now.month, now.day)
  end

new_version = new.to_s("%Y.%m.%d.%L")

shard[YAML::Any.new("version")] = YAML::Any.new(new_version)

File.write("shard.yml", shard.to_yaml)

puts "Updated our version to #{new_version}"
