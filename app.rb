# encoding: utf-8
require 'sinatra'
require 'json'
require 'httparty'
require 'date'
require 'redis'
require 'dotenv'

configure do
  # Load .env vars
  Dotenv.load
  # Disable output buffering
  $stdout.sync = true
  # Exclude messages that match this regex
  set :message_exclude_regex, /^(voxbot|tacobot|pkmn|cabot|cfbot|campfirebot|\/)/i
  
  # Set up redis
  case settings.environment
  when :development
    uri = URI.parse(ENV["LOCAL_REDIS_URL"])
  when :production
    uri = URI.parse(ENV["REDISCLOUD_URL"])
  end
  $redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

get '/' do
  'hi.'
end

get '/markov' do
  if params[:token] == ENV["OUTGOING_WEBHOOK_TOKEN"]
    status 200
    body build_markov
  else
    status 403
    body 'Nope.'
  end
end

post '/markov' do
  response = ''
  # Ignore if text is a cfbot command, or a bot response, or the outgoing integration token doesn't match
  unless params[:text].nil? || params[:text].match(settings.message_exclude_regex) || params[:user_id] == "USLACKBOT" || params[:token] != ENV["OUTGOING_WEBHOOK_TOKEN"]
    $redis.pipelined do
      store_markov(params[:text])
    end
    if rand <= ENV['RESPONSE_CHANCE'].to_f
      reply = build_markov
      puts "[LOG] Replying: #{reply}"
      response = { text: reply, link_names: 1 }.to_json
    end
  end
  
  status 200
  body response
end

def store_markov(text)
  # Downcase and remove Slack formatting, replace slack user ids with the proper username, and clean up some punctuation
  text = text.gsub(/<@([\w]+)>/){ |m| get_slack_username($1) }.gsub(/:-?\(/, ':disappointed:').gsub(/:-?\)/, ':smiley:').gsub(/<.*?>|&lt;.*?&gt;|[\*`_<>"\(\)“”•]/, '').gsub(/\n+/, ' ').gsub(/[‘’]/,'\'').downcase
  # Split words into array
  words = text.split(/\s+/)
  # Ignore if phrase is less than 3 words
  unless words.size < 3
    puts "[LOG] Storing: #{text}"
    (words.size - 2).times do |i|
      # Join the first two words as the key
      key = words[i..i+1].join(' ')
      # And the third as a value
      value = words[i+2]
      $redis.sadd(key, value)
    end
  end
end

def build_markov
  phrase = []
  # Get a random key (i.e. random pair of words) from Redis
  key = $redis.randomkey

  unless key.nil? || key.empty?
    # Split the key into the two words and add them to the phrase array
    key = key.split(' ')
    first_word = key.first
    second_word = key.last
    phrase << first_word
    phrase << second_word

    # With these two words as a key, get a third word from Redis
    # until there are no more words
    while phrase.size <= ENV["MAX_WORDS"].to_i && new_word = get_next_word(first_word, second_word)
      # Add the new word to the array
      phrase << new_word
      # Set the second word and the new word as keys for the next iteration
      first_word, second_word = second_word, new_word
    end
  end
  phrase.join(' ').strip
end

def get_next_word(first_word, second_word)
  $redis.srandmember("#{first_word} #{second_word}")
end

def get_slack_username(slack_id)
  # Wait a second so we don't get rate limited
  sleep 1
  username = ""
  uri = "https://slack.com/api/users.list?token=#{ENV["API_TOKEN"]}"
  request = HTTParty.get(uri)
  response = JSON.parse(request.body)
  if response['ok']
    user = response["members"].find { |u| u["id"] == slack_id }
    username = "@#{user["name"]}" unless user.nil?
  else
    puts "Error fetching username: #{response['error']}" unless response['error'].nil?
  end
  username
end

def get_channel_id(channel_name)
  # Wait a second so we don't get rate limited
  sleep 1
  uri = "https://slack.com/api/channels.list?token=#{ENV["API_TOKEN"]}"
  request = HTTParty.get(uri)
  response = JSON.parse(request.body)
  if response['ok']
    channel = response["channels"].find { |u| u["name"] == channel_name.gsub('#','') }
    channel_id = channel["id"] unless channel.nil?
  else
    puts "Error fetching channel name: #{response['error']}" unless response['error'].nil?
    ''
  end
end

def import_history(channel_id, ts = nil)
  # Wait 1 second so we don't get rate limited
  sleep 1
  uri = "https://slack.com/api/channels.history?token=#{ENV["API_TOKEN"]}&channel=#{channel_id}&count=1000"
  uri += "&latest=#{ts}" unless ts.nil?
  request = HTTParty.get(uri)
  response = JSON.parse(request.body)
  if response['ok']
    # Find all messages that are plain messages (no subtype), are not hidden, are not from a bot (integrations, etc.) and are not cfbot commands
    messages = response['messages'].find_all{ |m| m['subtype'].nil? && m['hidden'] != true && m['bot_id'].nil? && !m['text'].match(settings.message_exclude_regex)  }
    puts "Importing #{messages.size} messages from #{DateTime.strptime(messages.first['ts'],'%s').strftime('%c')}" if messages.size > 0
    
    $redis.pipelined do
      messages.each do |m|
        store_markov(m['text'])
      end
    end
    
    # If there are more messages in the API call, make another call, starting with the timestamp of the last message
    if response['has_more'] && !messages.last['ts'].nil?
      ts = messages.last['ts']
      import_history(channel_id, ts)
    end
  else
    puts "Error fetching channel history: #{response['error']}" unless response['error'].nil?
  end
end
