require "./app"

desc "Empties the entire database"
task :reset do
  start_time = Time.now
  puts "Emptying redis..."
  $redis.flushall
  puts "Completed in #{Time.now - start_time} seconds"
end

desc "Ingest the history of one or more Slack channels into the database"
task :ingest do
  if ENV["CHANNELS"].nil?
    puts "You need to specify the name of the channels you wish to import, e.g. rake import:channel CHANNELS=\"#random\""
  else
    options = {}
    start_time = Time.now
    channels = ENV["CHANNELS"].split(",")
    options[:user_id] = get_slack_user_id(ENV["USERNAME"]) unless ENV["USERNAME"].nil?
    options[:oldest] = (start_time - (60 * 60 * 24 * ENV["DAYS"].to_i)).to_i unless ENV["DAYS"].nil?
    channels.each do |channel|
      puts "\nImporting channel #{channel.strip} to #{ENV["RACK_ENV"]} (this will take a while)\n\n"
      channel_id = get_channel_id(channel.strip)
      import_history(channel_id, options)
    end
    puts "Completed in #{Time.now - start_time} seconds"
  end
end

desc "Empties the database and reingests the channel or channels"
task :reingest => ['reset', 'ingest']

task :topic do
  if ENV["CHANNEL"].nil?
    puts "You need to specify the name of the channel you wish to set the topic for."
  elsif !Time.now.saturday? && !Time.now.sunday?
    start_time = Time.now
    channel_id = get_channel_id(ENV["CHANNEL"].strip)
    topic = build_markov
    set_topic(channel_id, topic)
    puts "Completed in #{Time.now - start_time} seconds"
  end
end
