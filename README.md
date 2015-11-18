# snarkov

Snarkov is a Sinatra-based [Markov bot][mb] for [Slack][slack].

![](http://i.imgur.com/HJI9SLK.png)

[mb]: http://stackoverflow.com/questions/5306729/how-do-markov-chain-chatbots-work
[slack]: https://slack.com

## Installation

The simplest way to set up snarkov is using [Heroku][he] & Redis Cloud. Just press this button to deploy it:

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

If you'd rather deploy it it manually, install the [Heroku Toolbelt][ht], clone the repo, and run:

```
$ heroku create
$ heroku addons:add rediscloud
$ git push heroku master
```

Next, you'll want to set up a Slack [outgoing webhook][ow] to send messages to snarkov. Set it up so it listens to a single channel of your choice, _don't_ set up a keyword, and set the URL to `http://[your-heroku-url]/markov` (you can find out your Heroku URL with `heroku info`). Also, copy the integration's token, you'll need it later.

You'll also need a Slack API token. You can get one by going to [this page][token] while logged into Slack.

Finally, you'll have to set up the config vars for your Heroku app. You can set these up in the settings page for your app in the Heroku dashboard, or using the `heroku config:set` [command][cf]. The variables you'll need to set up are:

* `OUTGOING_WEBHOOK_TOKEN`: the token from the outgoing webhook you'll use.
* `API_TOKEN`: the Slack API token you got earlier.
* `RESPONSE_CHANCE`: the probability, from 0 to 1, that the bot will reply back to the channel when it receives a message. 1 makes it reply every time, 0 essentially turns it off. Set it to something sensible, like 0.1, unless you _really_ want to annoy your teammates.
* `MAX_WORDS`: the maximum number of words the bot can reply back. Set this to something sensible, like 100.
* `SEND_TWEETS`: the bot will tweet out whatever it says if this variable is present. You'll have to set up a [Twitter app][ta], and fill out the `TWITTER_API_KEY`, `TWITTER_API_SECRET`, `TWITTER_TOKEN`, and `TWITTER_TOKEN_SECRET` variables for it to work.

[ht]: https://toolbelt.heroku.com/
[he]: http://www.heroku.com
[ow]: https://slack.com/services/new/outgoing-webhook
[token]: https://api.slack.com/#auth
[cf]: https://devcenter.heroku.com/articles/config-vars#setting-up-config-vars-for-a-deployed-application
[ta]: http://apps.twitter.com

## Running locally

1. Install redis
2. Create a `.env` file and put the config variables there (see `.env.example`)
3. Run `bundle install`
4. Run `foreman start -f Procfile.dev`
5. Send POST requests to `http://localhost:5000/markov` to populate it, with the `text` parameter being the message's text, and `token` the outgoing webhook's token.
6. Send GET requests to `http://localhost:5000/markov?token=[OUTGOING_WEBHOOK_TOKEN]` to see a random reply

## Usage

After snarkov is up and running, the outgoing webhook you set up will send every message in the channel you selected (except those from other integrations) to snarkov, which will process and store it for future usage. It might respond with a Markov-generated message of its own, depending on the number you have set in the `RESPONSE_CHANCE` environment variable, with 0 meaning it will never respond, and 1 meaning it'll respond every single time.

If you have a Mac, a fun thing to do is run this in the terminal:

```
$ curl -s http://[your-heroku-url]/markov?token=[outgoing-webhook-token] | say -i
```

## Importing channels

Snarkov works better if it has a lot of text to work with. To help populate it, you can feed it the entire history of a list of Slack channels. **Warning:** Depending on how many messages are in the channel's history, this might take a long time, and potentially fill up your free Redis Cloud account very quickly. You'll probably want to go to your Heroku dashboard and upgrade your Redis Cloud account to one of the paid levels before doing this.

To populate your local redis for dev/testing, use:

```
$ rake import:channel CHANNELS='#channel-name'
```

To populate redis in production, run:

```
$ heroku run rake import:channel CHANNELS='#channel-name'
```

The `import:channel` task takes a single channel name, or a comma-separated list of channel names, e.g.: 

```
$ heroku run rake import:channel CHANNELS='#random,#general'
```

If you want to import a channel's history going back only a certain number of days, you can add a `DAYS` option. For example:

```
$ heroku run rake import:channel CHANNELS='#random,#general' DAYS=5
```

This will import the last 5 days of chat history from the #random and #general channels.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License 

Copyright (c) 2014, Guillermo Esteves
All rights reserved.

BSD license

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
