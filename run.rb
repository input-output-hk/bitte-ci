#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'logger'
require 'securerandom'
require './db'

payload = $stdin.read
json = JSON.parse(payload)
uuid = SecureRandom.uuid

Event.insert(
  payload: Sequel.pg_json_wrap(json),
  id: uuid,
  step: 'received',
  created_at: Time.now,
  updated_at: Time.now
)

hcl = File.read('job.hcl')

hcl.gsub!('@@PAYLOAD@@', payload)
hcl.gsub!('@@UUID@@', uuid)
hcl.gsub!('@@FLAKE@@', '.#bitte-ci-env')

hcl.gsub!(/@@([^@]+)@@/) do
  match = Regexp.last_match(1)
  json.dig(*match.split('.')) || match
end

Tempfile.open 'job.hcl' do |file|
  file.write hcl
  file.flush
  system 'nomad', 'job', 'run', file.path
end

Event.where(id: uuid).update(step: 'queued', updated_at: Time.now)
