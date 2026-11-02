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

**AI chat:** once an admin runs `!neuronactivate`, every message in that channel (except commands) gets an AI reply. The bot remembers the conversation until AI mode is turned on again. AI chat can only be active in one channel at a time.

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

Create a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). AI chat uses the `gpt-4.1-nano` model, which is cheap but **not free**: you need credit on your OpenAI account.

### 4. Download the code and install dependencies

```bash
git clone https://github.com/JusttPiee/CakeeBot.git
cd CakeeBot
bundle install
```

(Or on GitHub, click **Code → Download ZIP**, unzip it, open a terminal in that folder and run `bundle install`.)

### 5. Run the bot

On Windows, double-click **`start.bat`**. On any system, you can also run:

```bash
ruby cakee.rb
```

**The first time**, the bot asks for your keys in the terminal:

```
Paste your Discord bot token (input is hidden):
✅ Saved DISCORD_BOT_TOKEN to .env
Paste your OpenAI API key (input is hidden):
✅ Saved OPENAI_API_KEY to .env
🤖 Cake is alive!
```

Your keys are saved to a `.env` file next to `cakee.rb`, so after that the bot starts with no questions. While you paste, nothing shows on screen. That's normal: it hides the keys.

### 6. Add the bot to your server

Type `!invite` in any channel the bot can already see, or build the link yourself:

```
https://discord.com/oauth2/authorize?client_id=YOUR_APPLICATION_ID&scope=bot&permissions=84992
```

`YOUR_APPLICATION_ID` is on the **General Information** page of your app in the Developer Portal. The link asks only for what the bot needs: View Channels, Send Messages, Embed Links and Read Message History.

Then type `!help` in your server to get started. 🎉

---

## Configuration

All settings live in `.env`. See `.env.example` for a template. You can also set them as normal environment variables, which is handy on servers or with Docker.

| Variable | Required | Description |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Yes | Your Discord bot token |
| `OPENAI_API_KEY` | Yes | Your OpenAI API key |
| `DISCORD_INVITE_URL` | No | A custom link for `!invite`. If empty, the bot builds one automatically |

To change a key, edit `.env` or delete it. The bot will ask again on the next run.

**Personalize (optional):** you can edit the embeds (titles, colors, footers) in `cakee.rb`. Or leave them as they are, and I get credited haha.

### Files the bot uses

| File | Purpose |
|---|---|
| `.env` | Your secret keys. **Never share or commit this file**; it's already in `.gitignore` |
| `badwords.txt` | The bad words list, one word per line. You can edit it by hand or with `!badword` |
| `ai_config.txt` | Created automatically. Remembers which channel has AI chat on |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `bundle: command not found` | Run `gem install bundler` |
| The bot is online but ignores messages | Turn on **Message Content Intent** (step 2) and restart the bot |
| The bot closes right away with an intents/connection error | Turn on all three privileged intents (step 2) |
| `Missing DISCORD_BOT_TOKEN` (no prompt shown) | The bot isn't running in an interactive terminal. Set the variable or create `.env` by hand |
| The token is rejected (401 Unauthorized) | The token is wrong or was reset. Delete the line from `.env` and run the bot again |
| AI doesn't reply | Check your OpenAI key and account credit, and look at the terminal for errors |
| `!help` or `!invite` shows nothing | The bot needs the **Embed Links** permission in that channel |

---

## Security

- **Never** put your token or API key in the code or post them anywhere. If one leaks, reset it right away in the Discord Developer Portal or on the OpenAI dashboard.
- `.env` is git-ignored, so it won't be uploaded. It also won't follow you to another computer: on a new machine, the bot will ask for your keys again on the first run.

---

## License

MIT License (see the [LICENSE](LICENSE) file).
