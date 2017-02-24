# encoding: utf-8
require 'sinatra'
require 'json'
require 'httparty'
require 'date'
require 'redis'
require 'dotenv'
require 'dalli'
require 'aws-sdk'
require 'tempfile'

configure do
  # Load .env vars
  Dotenv.load
  # Disable output buffering
  $stdout.sync = true

  # Don't store messages that match this regex
  if ENV['IGNORE_REGEX'].nil?
    set :ignore_regex, nil
  else
    set :ignore_regex, Regexp.new(ENV['IGNORE_REGEX'], 'i')
  end

  # Respond to messages that match this
  if ENV['REPLY_REGEX'].nil?
    set :reply_regex, nil
  else
    set :reply_regex, Regexp.new(ENV['REPLY_REGEX'], 'i')
  end

  # Mute if this message is received
  set :mute_regex, Regexp.new(ENV['MUTE_REGEX'], 'i')

  # Set up redis
  case settings.environment
  when :development
    uri = URI.parse(ENV['LOCAL_REDIS_URL'])
  when :production
    uri = URI.parse(ENV['REDISCLOUD_URL'] || ENV['REDIS_URL'])
  end
  $redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)

  if ENV['MEMCACHEDCLOUD_SERVERS'].nil?
    $memcached = Dalli::Client.new('localhost:11211')
  else
    $memcached = Dalli::Client.new(ENV['MEMCACHEDCLOUD_SERVERS'].split(','), username: ENV['MEMCACHEDCLOUD_USERNAME'], password: ENV['MEMCACHEDCLOUD_PASSWORD'])
  end
end

get '/' do
  'hi.'
end

options '/markov' do
  status 200
  headers 'Access-Control-Allow-Origin' => '*'
  headers 'Access-Control-Allow-Methods' => 'OPTIONS, GET'
  headers 'Access-Control-Allow-Headers' => 'Content-Type'
  body ''
end

get '/markov' do
  if params[:token] == ENV['OUTGOING_WEBHOOK_TOKEN'] || settings.environment == :development
    status 200
    headers 'Access-Control-Allow-Origin' => '*'
    body build_markov
  else
    status 403
    body 'Nope.'
  end
end

post '/markov' do
  begin
    response = ''
    if is_valid_message?(params)
      if is_mute_command?(params)
        response = mute_bot(params[:text])
      else
        store_message(params[:text]) if should_store_message?(params)
        response = build_markov(params) if should_reply?(params)
      end
    end
  rescue => e
    response = "[ERROR] #{e}"
    puts response
  end

  status 200
  body json_response_for_slack(response)
end

# If the token matches and the message didn't come from a bot,
# it's valid
def is_valid_message?(params)
  settings.environment == :development || (params[:token] == ENV['OUTGOING_WEBHOOK_TOKEN'] && params[:bot_id].nil?)
end

def is_mute_command?(params)
  params[:text].match(settings.mute_regex)
end

# If the bot isn't muted,
# and the ignore keyword is not invoked,
# and the reply keyword is invoked or the rand check passes,
# then the bot will send back a reply.
def should_reply?(params)
  !$redis.exists('snarkov:shush') &&
  (settings.ignore_regex.nil? || !params[:text].match(settings.ignore_regex)) &&
  (rand <= ENV['RESPONSE_CHANCE'].to_f || (!settings.reply_regex.nil? && params[:text].match(settings.reply_regex)))
end

# If the reply keyword isn't invoked and the ignore keyword isn't invoked,
# store the message as a markov chain.
# If the SLACK_USER env variable is set, store only if the message came from that user.
def should_store_message?(params)
  (settings.ignore_regex.nil? || !params[:text].match(settings.ignore_regex)) &&
  (settings.reply_regex.nil? || !params[:text].match(settings.reply_regex)) &&
  (ENV['SLACK_USER'].nil? || ENV['SLACK_USER'] == params[:user_name] || ENV['SLACK_USER'] == params[:user_id])
end

def store_message(text)
  $redis.pipelined do
    process_markov(text)
  end
end

def process_markov(text)
  # Split long text into sentences
  sentences = text.split(/\.\s+|\n+/)
  sentences.each do |t|
    # Horrible chain of regex to simplify and normalize strings
    text = t.gsub(/<@([\.\w|-]+)>:?/){ |m| get_slack_name($1) }       # Replace user tags with first names
            .gsub(/<#([\w|-]+)>/){ |m| get_channel_name($1) }         # Replace channel tags with channel names
            .gsub(/<.*?>:?/, '')                                      # Remove links
            .gsub(/:-?\(/, ':disappointed:')                          # Replace :( with :dissapointed:
            .gsub(/:-?\)/, ':smiley:')                                # Replace :) with :smiley:
            .gsub(/;-?\)/, ':wink:')                                  # Replace ;) with :wink:
            .gsub(/<3|&lt;3/, ':heart:')                              # Replace <3 with :heart:
            .gsub(/¯\\_\(ツ\)_\/¯/, ':shrug:')                        # Replace shrugs
            .gsub(/[‘’]/,'\'')                                        # Replace single curly quotes with straight quotes
            .gsub(/\s_|_\s|_[,\.\?!]|^_|_$/, ' ')                     # Remove underscores for _emphasis_
            .gsub(/&lt;.*?&gt;|&lt;|&gt;|[\*`<>'"“”•~\(\)\[\]{}]|^\s*-/, '') # Remove extraneous characters
            .gsub(/[,;.\s]+$/, '')                                    # Remove trailing punctuation
            .gsub(/:shrug:/, '¯\_(ツ)_/¯')                            # Put the shrug back
            .downcase
            .strip
    if text.size >= 3
      puts "[LOG] Storing: \"#{text}\""
      # Split words into array
      words = text.split(/\s+/)
      if words.size < 3
        $redis.rpush('snarkov:initial_words', words.join(' '))
      else
        (words.size - 2).times do |i|
          # Join the first two words as the key
          key = words[i..i+1].join(' ')
          # And the third as a value
          value = words[i+2]
          # If it's the first pair of words, store in special set
          $redis.rpush('snarkov:initial_words', key) if i == 0
          $redis.rpush(key, value)
        end
      end
    end
  end
end

def mute_bot(text)
  time = text.scan(/\d+/).first.nil? ? 60 : text.scan(/\d+/).first.to_i
  minutes = [[time.abs, 60].min, 0].max
  $redis.setex('snarkov:shush', minutes * 60, 'true')
  puts "[LOG] Shutting up: #{minutes} minutes"
  ['😴', '🤐', '😶'].sample
end

def build_markov(opts = {})
  options = { max_words: ENV['MAX_WORDS'].to_i }.merge(opts)
  phrase = []
  # Get a random pair of words from Redis
  initial_words = $redis.lrange('snarkov:initial_words', 0, -1).sample

  unless initial_words.nil?
    puts "[LOG] Starting sentence with \"#{initial_words}\""
    # Split the key into the two words and add them to the phrase array
    initial_words = initial_words.split(' ')
    if initial_words.size == 1
      phrase << initial_words.first
    else
      first_word = initial_words.first
      second_word = initial_words.last
      phrase << first_word
      phrase << second_word

      # With these two words as a key, get a third word from Redis
      # until there are no more words
      while phrase.size <= options[:max_words] && new_word = get_next_word(first_word, second_word)
        # Add the new word to the array
        phrase << new_word
        # Set the second word and the new word as keys for the next iteration
        first_word, second_word = second_word, new_word
      end
    end
  end
  reply = phrase.join(' ').strip
  puts "[LOG] Speaking: \"#{reply}\""
  reply
end

def get_next_word(first_word, second_word)
  responses = $redis.lrange("#{first_word} #{second_word}", 0, -1)
  next_word = responses.sample
  puts responses.size == 0 ? "[LOG]     \"#{first_word} #{second_word}\" -> #{responses.to_s}" : "[LOG]     \"#{first_word} #{second_word}\" -> #{responses.to_s} -> \"#{next_word}\""
  next_word
end

def markov_topic(channel_id)
  now = Time.now.getlocal('-05:00')
  chance = ENV['TOPIC_CHANGE_CHANCE'].nil? ? 0.1 : ENV['TOPIC_CHANGE_CHANCE'].to_f
  if !$redis.exists("snarkov:topic_set:#{channel_id}") && rand < chance && !now.saturday? && !now.sunday? && now.hour.between?(9, 18)
    topic = ''
    while topic.size < 3 || topic.size > 250
      topic = build_markov
    end
    set_topic(channel_id, topic)
    $redis.setex("snarkov:topic_set:#{channel_id}", 24 * 60 * 60, 'true')
  end
end

def json_response_for_slack(reply)
  response = { text: reply, link_names: 1 }
  response[:username] = ENV['BOT_USERNAME'] unless ENV['BOT_USERNAME'].nil?
  response[:icon_emoji] = ENV['BOT_ICON'] unless ENV['BOT_ICON'].nil?
  response.to_json
end

def get_slack_name(slack_id)
  slack_id = slack_id.split('|').first
  cache_key = "slack:user:#{slack_id}"
  name = $memcached.get(cache_key)

  if name.nil?
    uri = "https://slack.com/api/users.info?token=#{ENV['API_TOKEN']}&user=#{slack_id}"
    request = HTTParty.get(uri)
    response = JSON.parse(request.body)
    if response['ok']
      user = response['user']
      if !user['profile'].nil? && !user['profile']['first_name'].nil?
        name = user['profile']['first_name']
      else
        name = user['name']
      end
    else
      name = ''
      puts "[ERROR] fetching user: #{response['error']}" unless response['error'].nil?
    end
    $memcached.set(cache_key, name, 60 * 60 * 24 * 30)
  end
  name
end

def get_slack_user_id(username)
  cache_key = "slack:user_id:#{username}"
  user_id = $memcached.get(cache_key)

  if user_id.nil?
    users_list = get_users_list
    if !users_list.nil?
      users = JSON.parse(users_list)['members']
      user = users.find { |u| u['name'] == username.downcase }
      user_id = user['id'] unless user.nil?
      $memcached.set(cache_key, user_id, 60 * 60 * 24 * 365)
    end
  end

  user_id
end

def get_users_list
  cache_key = 'slack:users_list'
  users_list = $memcached.get(cache_key)
  if users_list.nil?
    uri = "https://slack.com/api/users.list?token=#{ENV['API_TOKEN']}"
    request = HTTParty.get(uri)
    response = JSON.parse(request.body)
    if response['ok']
      users_list = request.body
      #$memcached.set(cache_key, users_list, 60 * 60 * 24)
    else
      puts "[ERROR] Error fetching user ID: #{response['error']}" unless response['error'].nil?
    end
  end
  users_list
end

def get_channel_id(channel_name)
  cache_key = "slack:channel_id:#{channel_name}"
  channel_id = $memcached.get(cache_key)

  if channel_id.nil?
    channels_list = get_channels_list
    if !channels_list.nil?
      channels = JSON.parse(channels_list)['channels']
      channel = channels.find { |c| c['name'] == channel_name.gsub('#','') }
      channel_id = channel['id'] unless channel.nil?
      $memcached.set(cache_key, channel_id, 60 * 60 * 24 * 365)
    end
  end

  channel_id
end

def get_channels_list
  cache_key = 'slack:channels_list'
  channels_list = $memcached.get(cache_key)
  if channels_list.nil?
    uri = "https://slack.com/api/channels.list?token=#{ENV['API_TOKEN']}"
    request = HTTParty.get(uri)
    response = JSON.parse(request.body)
    if response['ok']
      channels_list = request.body
      $memcached.set(cache_key, channels_list, 60 * 60 * 24)
    else
      puts "[ERROR] Error fetching channel id: #{response['error']}" unless response['error'].nil?
    end
  end
  channels_list
end

def get_channel_name(channel_id)
  cache_key = "slack:channel:#{channel_id}"
  channel_name = $memcached.get(cache_key)

  if channel_name.nil?
    channel = channel_id.split('|')
    if channel.size == 1
      uri = "https://slack.com/api/channels.info?token=#{ENV['API_TOKEN']}&channel=#{channel.first}"
      request = HTTParty.get(uri)
      response = JSON.parse(request.body)
      if response['ok']
        channel_name = "##{response['channel']['name']}"
      else
        channel_name = ''
        puts "[ERROR] Error fetching channel name: #{response['error']}" unless response['error'].nil?
      end
    else
      channel_name = "##{channel.last}"
    end
    $memcached.set(cache_key, channel_name, 60 * 60 * 24 * 30)
  end

  channel_name
end

def import_history(channel_id, opts = {})
  options = { oldest: 0 }.merge(opts)
  uri = "https://slack.com/api/channels.history?token=#{ENV['API_TOKEN']}&channel=#{channel_id}&count=1000"
  uri += "&latest=#{options[:latest]}" unless options[:latest].nil?
  request = HTTParty.get(uri)
  response = JSON.parse(request.body)
  if response['ok']
    # Find all messages that are plain messages (no subtype), are not hidden, and came from a human
    messages = response['messages'].select { |m| m['subtype'].nil? && m['hidden'] != true && !m['user'].nil? && m['bot_id'].nil? }

    # Reject messages that match the ignore and reply keywords
    messages.reject! { |m| m['text'].match(settings.ignore_regex) } unless settings.ignore_regex.nil?
    messages.reject! { |m| m['text'].match(settings.reply_regex) } unless settings.reply_regex.nil?

    # Filter by user id, if necessary
    messages.select! { |m| m['user'] == options[:user_id] } unless options[:user_id].nil?

    if messages.size > 0
      puts "\nImporting #{messages.size} messages from #{DateTime.strptime(messages.first['ts'],'%s').strftime('%c')} to #{DateTime.strptime(messages.last['ts'],'%s').strftime('%c')}\n\n" if messages.size > 0
      messages.each do |m|
        process_markov(m['text']) if m['ts'].to_i > options[:oldest]
      end
    end

    # If there are more messages in the API call, make another call, starting with the timestamp of the last message
    if response['has_more'] && !response['messages'].last['ts'].nil? && response['messages'].last['ts'].to_i > options[:oldest]
      options[:latest] = response['messages'].last['ts']
      import_history(channel_id, options)
    end
  else
    puts "[ERROR] Error fetching channel history: #{response['error']}" unless response['error'].nil?
  end
end

def set_topic(channel_id, topic)
  uri = 'https://slack.com/api/channels.setTopic'
  request = HTTParty.post(uri, body: {
    token: ENV['API_TOKEN'],
    channel: channel_id,
    topic: topic
  })
  response = JSON.parse(request.body)
  if response['ok']
    puts "[LOG] Channel topic set to \"#{topic}\""
  else
    puts "[ERROR] Error setting channel topic: #{response['error']}"
  end
end
