# frozen_string_literal: true

require 'date'
require 'logger'
require 'redis'
require 'twilio-ruby'

class Peep
  attr_accessor :name, :number

  def initialize(name)
    @name = name
    @number = ENV[name.upcase]
  end
end

class Storage
  class << self
    def week
      return redis.get('week').to_i if redis.exists?('week')

      self.week = 1
      week
    end

    def week=(new_week)
      redis.set('week', new_week)
    end

    def last_notified
      return DateTime.strptime(redis.get('last_notified')) if redis.exists?('last_notified')

      DateTime.new
    end

    def last_notified=(date)
      redis.set('last_notified', date)
    end

    def redis
      @redis ||= Redis.new(url: ENV['REDIS_TLS_URL'])
    end
  end
end

class ChoreReminderer
  class << self
    CHORES = {
      kitchen: 'Kitchen this week',
      stairs: 'Stairs this week (and 2f bathroom if you use it...)',
      bins: 'Bins (picked up Thursday or Monday)'
    }
    PEEPS = {
      lexy: Peep.new('Lexy'),
      ash: Peep.new('Ash'),
      lorenzo: Peep.new('Lorenzo'),
      kevin: Peep.new('Kevin'),
      ellie: Peep.new('Ellie'),
      ang: Peep.new('Ang')
    }.freeze

    def notify!
      if !should_notify?(Storage.last_notified)
        logger.error("Not notifying, to soon after last notification")
        return nil
      end

      week = Storage.week

      kitchen = house[week % house.length]
      stairs = stairs_peep(kitchen)
      bins = bins_peep(kitchen)

      logger.info("Notifying! kitchen: #{kitchen.name}, stairs: #{stairs.name}, bins: #{bins.name}")

      { kitchen: kitchen, stairs: stairs, bins: bins}.each do |chore, peep|
        begin
          Messenger.sms(peep, message(chore))
        rescue Twilio::REST::RestError => e
          logger.error(e.message)
        end
      end

      Storage.week += 1
      Storage.last_notified = DateTime.now
    end

    private

    def logger
      @logger ||= Logger.new('chore-notifier.log', 'monthly')
    end

    def should_notify?(date)
      return true if DateTime.now.sunday? && DateTime.now.mjd - date.mjd >= 6

      false
    end

    def message(chore)
      "Yo yo yo it's your turn to do the #{CHORES[chore]}. Get hustling!"
    end

    def stairs_peep(peep)
      {
        kevin: PEEPS[:lexy],
        ash: PEEPS[:ellie],
        ang: PEEPS[:lorenzo],
        lexy: PEEPS[:kevin],
        ellie: PEEPS[:ash],
        lorenzo: PEEPS[:ang]
      }[peep.name.downcase.to_sym]
    end

    def bins_peep(peep)
      {
        kevin: PEEPS[:lorenzo],
        ash: PEEPS[:ang],
        ang: PEEPS[:ash],
        lexy: PEEPS[:ellie],
        ellie: PEEPS[:lexy],
        lorenzo: PEEPS[:kevin]
      }[peep.name.downcase.to_sym]
    end

    def house
      @house ||= PEEPS.map { |_k, v| v }
    end
  end
end

class Messenger
  class << self
    def sms(to, message)
      client.messages.create(
        from: ENV['APP_ENV'] == 'production' ? ENV['TWILIO_SEND'] : ENV['TWILIO_SEND_TEST'],
        to: to.number,
        body: message
      )
    end

    def client
      @client if @client
      @client = Twilio::REST::Client.new ENV['TWILIO_SID'], ENV['TWILIO_TOKEN']
      @client.logger = Logger.new('twilio.log')
      @client
    end
  end
end
