if ENV['APP_ENV'] == 'development'
  require 'dotenv/load'
  Dotenv.load
end

require_relative './chore-reminderer'

ChoreReminderer.notify!
