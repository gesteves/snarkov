require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel, :channel_list do |t, args|
    if args.channel_list.nil?
      puts "You need to specify the name of the channel you wish to import, e.g. rake import:channel[random]"
    else
      channels = args.channel_list.split(',')
      channels.each do |channel|
        puts "Importing channel #{channel.strip} to #{ENV["RACK_ENV"]} (this will take a while)"
        channel_id = get_channel_id(channel.strip)
        import_history(channel_id)
      end
    end
  end
end
