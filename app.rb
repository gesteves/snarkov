require 'sinatra'
require 'json'

configure do
  require 'redis'
  uri = URI.parse(ENV["REDISCLOUD_URL"])
  $redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

get '/' do
  'hi.'
end

post '/markov' do
  # Ignore if text is a cfbot command, or a bot response, or the outgoing integration token doesn't match
  unless params[:text].match(/^(cfbot|campfirebot|\/)/i) || params[:user_id] == "USLACKBOT" || params[:token] != ENV["OUTGOING_WEBHOOK_TOKEN"]
    store_markov(params[:text])
  end
  
  if rand <= ENV['RESPONSE_CHANCE'].to_f
    response = { text: build_markov }.to_json
  else
    response = ''
  end
  
  status 200
  body response
end


def store_markov(text)
  # Downcase and remove punctuation
  text = text.downcase.gsub(/[^\w\s]+/, '')
  # Split words into array
  words = text.split(/\s+/).reject{ |w| w.match(/^http/) }
  # Ignore if phrase is less than 3 words
  unless words.size < 3
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
    while new_word = get_next_word(first_word, second_word)
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
