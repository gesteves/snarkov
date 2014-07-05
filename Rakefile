require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel, :channel_id do |t, args|
    if args.channel_id.nil?
      puts "You need to specify the ID of the channel you wish to import, e.g. rake import:channel[abc123]"
    else
      puts "Importing channel #{get_channel_name(args.channel_id)} (this will take a while)"
      import_history(args.channel_id)
    end
  end
end
