# Turn a time into "just now", "5 minutes ago", "2 hours ago", "3 days ago".
# Used to show the AI how old each message is, so it doesn't treat a message from days ago as new.
def time_ago(time, now = Time.now)
  seconds = (now - time).to_i
  return "just now" if seconds < 60

  minutes = seconds / 60
  return amount_ago(minutes, "minute") if minutes < 60

  hours = minutes / 60
  return amount_ago(hours, "hour") if hours < 24

  amount_ago(hours / 24, "day")
end

# amount_ago(1, "hour") => "1 hour ago", amount_ago(3, "hour") => "3 hours ago"
def amount_ago(amount, unit)
  unit += "s" unless amount == 1
  "#{amount} #{unit} ago"
end
