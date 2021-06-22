# frozen_string_literal: true

require 'sequel'
require 'logger'

Sequel.extension :pg_json_ops
Sequel::Model.plugin :timestamps

DB = Sequel.connect('postgres://postgres@127.0.0.1/bitte_ci')
DB.extension :pg_json
DB.logger = Logger.new($stdout)
DB.wrap_json_primitives = true

class Event < Sequel::Model
end
