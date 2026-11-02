# Cakee Discord Bot

A multifunctional Discord bot written in Ruby. It can:

- 🧠 **Chat with AI** (OpenAI) in a channel you choose
- 🧹 **Filter profanity** with a word list that admins manage
- 🎮 **Play a word chain game** in English

---

## Commands

| Command | Who | What it does |
|---|---|---|
| `!help` | Everyone | Shows the command list |
| `!ping` | Everyone | Checks that the bot is online |
| `!invite` | Everyone | Sends a link to add the bot to another server |
| `!play` | Everyone | Starts a word chain game |
| `!stop` | Everyone | Stops the word chain game |
| `!badword add <word>` | Admins | Adds a word to the bad words list |
| `!badword remove <word>` | Admins | Removes a word from the list |
| `!badword list` | Admins | Shows the list |
| `!neuronactivate` | Admins | Turns on AI chat in the current channel |
| `!neurondeactivate` | Admins | Turns off AI chat |

**Word chain rules:** each word must be a real English word, can't be reused, and must start with the last letter of the previous word. The same person can't go twice in a row. After 3 wrong attempts, the game ends and the last player with a valid word wins.

**AI chat:** once an admin runs `!neuronactivate`, every message in that channel (except commands) gets an AI reply. The bot knows who is speaking (by nickname and user ID) and remembers the last 20 messages of the conversation (up to about 5,000 tokens), so API costs stay low. It forgets the conversation when the bot restarts or AI mode is turned on again. Replies longer than Discord's 2000-character limit are split into several messages. AI chat can only be active in one channel at a time.

---

## Setup

### 1. Install Ruby

- **Ruby 3.3.7 or newer.** On Windows, use [RubyInstaller](https://rubyinstaller.org/) (the "with Devkit" version).
- **Bundler**, which usually comes with Ruby. If it's missing, run `gem install bundler`.

Check that both work:

```bash
ruby -v
bundle -v
```

### 2. Create your Discord bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and click **New Application**.
2. Open the **Bot** tab:
   - Click **Reset Token** and copy the token. You'll paste it in step 5. **Keep it secret.**
   - Under **Privileged Gateway Intents**, turn on all three: **Presence Intent**, **Server Members Intent** and **Message Content Intent**. Then click **Save Changes**.

> ⚠️ If you skip the intents, the bot won't connect, or it won't be able to read messages, so the filter, game and AI won't work.

### 3. Get an OpenAI API key

Create a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). AI chat uses the `gpt-6-luna` model by default (change it with `OPENAI_MODEL` in `.env`), which is cheap but **not free**: you need credit on your OpenAI account.

### 4. Download the code and install dependencies

```bash
git clone https://github.com/JusttPiee/CakeeBot.git
cd CakeeBot
bundle install
```

(Or on GitHub, click **Code → Download ZIP** and unzip it.)

On Windows you can skip `bundle install`: `start.bat` installs anything missing for you.

### 5. Run the bot

On Windows, double-click **`start.bat`**. On any system, you can also run:

```bash
bundle exec ruby cakee.rb
```

**The first time**, the bot creates `.env` from `.env.example` and asks for your keys in the terminal:

```
📄 No .env found, created one from .env.example
Paste your Discord bot token (input is hidden):
✅ Saved DISCORD_BOT_TOKEN to .env
⏳ Checking DISCORD_BOT_TOKEN with Discord...
✅ Discord accepted DISCORD_BOT_TOKEN
Paste your OpenAI API key (input is hidden):
✅ Saved OPENAI_API_KEY to .env
🧠 AI model: gpt-6-luna (default)
⏳ Checking OPENAI_API_KEY with OpenAI...
✅ OpenAI accepted OPENAI_API_KEY
⏳ Connecting to Discord...
🤖 Cake is alive! Logged in as Cakee#1234 in 1 server(s)
```

(Each line also starts with a timestamp.) While you paste, nothing shows on screen. That's normal: it hides the keys. After that, the bot starts with no questions. If a key is wrong, the bot stops right away and tells you which one.

### 6. Add the bot to your server

Type `!invite` in any channel the bot can already see, or build the link yourself:

```
https://discord.com/oauth2/authorize?client_id=YOUR_APPLICATION_ID&scope=bot&permissions=84992
```

`YOUR_APPLICATION_ID` is on the **General Information** page of your app in the Developer Portal. The link asks only for what the bot needs: View Channels, Send Messages, Embed Links and Read Message History.

Then type `!help` in your server to get started. 🎉

---

## Configuration

All settings live in `.env`, which the bot creates from `.env.example` on the first run. Every setting is listed there with an explanation: edit `.env` and restart the bot to change one. Don't edit `.env.example`; the bot doesn't read it after the first run.

You can also set them as normal environment variables, which is handy on servers or with Docker. A system environment variable **wins over `.env`**; the bot prints a warning when that happens.

| Variable | Required | Description |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Yes | Your Discord bot token |
| `OPENAI_API_KEY` | Yes | Your OpenAI API key |
| `OPENAI_MODEL` | No | OpenAI model for AI chat. Default: `gpt-6-luna` |
| `OPENAI_TEMPERATURE` | No | Reply randomness (e.g. `0.7`). Leave empty if your model only supports the default |
| `DISCORD_INVITE_URL` | No | A custom link for `!invite`. If empty, the bot builds one automatically |

To change a key, edit it in `.env`, or clear its value (leave `KEY=` empty) and the bot will ask again on the next run.

**Personalize (optional):** you can edit the embeds (titles, colors, footers) in `cakee.rb`. Or leave them as they are, and I get credited haha.

### Files the bot uses

| File | Purpose |
|---|---|
| `.env` | Your secret keys. **Never share or commit this file**; it's already in `.gitignore` |
| `badwords.txt` | The bad words list, one word per line. You can edit it by hand or with `!badword` |
| `ai_config.txt` | Created automatically. Remembers which channel has AI chat on |
| `prompts/personality.txt` | The AI's personality: who it is and what it can do. Edit freely; `{bot_name}` becomes your bot's name. Changes apply on the next message |

### Running tests

The tests don't connect to Discord or OpenAI, so they're free and take about a second:

```bash
bundle exec ruby test/run_all.rb
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `bundle: command not found` / `Bundler not found` | Run `gem install bundler` |
| `cannot load such file -- discordrb` | Gems aren't installed. Run `bundle install`, or start the bot with `start.bat` |
| The bot is online but ignores messages | Turn on **Message Content Intent** (step 2) and restart the bot |
| The bot closes right away with an intents/connection error | Turn on all three privileged intents (step 2) |
| `Missing DISCORD_BOT_TOKEN` (no prompt shown) | The bot isn't running in an interactive terminal. Set the variable or create `.env` by hand |
| `Discord rejected DISCORD_BOT_TOKEN` | The token is wrong or was reset. Fix it in `.env`, or clear its value and run the bot again |
| `OpenAI rejected OPENAI_API_KEY` | The key is wrong (OpenAI keys start with `sk-`). Fix it in `.env`, or clear its value and run the bot again |
| You fixed `.env` but the bot still uses the old key | A system environment variable is overriding `.env` (the bot warns about this). Remove the variable and open a new terminal |
| AI says "My AI brain is unavailable" | Check the terminal. `model_not_found` means OpenAI retired the model: set a newer one in `OPENAI_MODEL` ([list of retired models](https://platform.openai.com/docs/deprecations)). Otherwise check your account credit |
| `!help` or `!invite` shows nothing | The bot needs the **Embed Links** permission in that channel |

---

## Security

- **Never** put your token or API key in the code or post them anywhere. If one leaks, reset it right away in the Discord Developer Portal or on the OpenAI dashboard.
- `.env` is git-ignored, so it won't be uploaded. It also won't follow you to another computer: on a new machine, the bot will ask for your keys again on the first run.

---

## License

MIT License (see the [LICENSE](LICENSE) file).
