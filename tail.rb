#!/usr/bin/env ruby
# frozen_string_literal: true

require 'uri'
require 'open3'
require 'json'

uuid = ARGV[0]

uri = URI('ws://127.0.0.1:3100/loki/api/v1/tail')
uri.query = URI.encode_www_form(
  # 'query' => %({nomad_group_name="#{uuid}"})
  'query' => %({nomad_group_name="#{uuid}"}),
  'delay_for' => '5'
)

puts uri

Open3.popen2e('websocat', uri.to_s) do |_si, soe|
  soe.each_line do |line|
    json = JSON.parse(line)
    json['streams'].each do |stream|
      # TODO: unify stderr/stdout somehow
      next unless stream['stream']['filename'] =~ %r{^/alloc/logs/runner\.stdout\..+}

      pp stream

      stream['values'].each do |(_time, value)|
        puts value
      end
    end
  end
end
