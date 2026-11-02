# Discord rejects messages over 2000 characters, so long AI replies are split into several messages.
# Splits happen between lines where possible, and between words for a single very long line.

DISCORD_LIMIT = 1900 # a bit under 2000 to stay safe

# Fill a chunk line by line; when the next line does not fit, start a new chunk.
def split_message(text)
  chunks = [""]
  split_into_lines(text).each do |line|
    chunks << "" if chunks.last.length + line.length > DISCORD_LIMIT
    chunks.last << line
  end
  chunks.reject { |chunk| chunk.strip.empty? } # Discord also rejects empty messages
end

# Break the text into lines, and break any line that is too long on its own into smaller pieces
def split_into_lines(text)
  lines = []
  text.each_line do |line|
    if line.length > DISCORD_LIMIT
      lines.concat(split_long_line(line))
    else
      lines << line
    end
  end
  lines
end

# Cut a long line at the last space that fits. If there is no space (e.g. a very long URL), cut at the limit.
def split_long_line(line)
  pieces = []
  while line.length > DISCORD_LIMIT
    cut = line.rindex(" ", DISCORD_LIMIT - 1)
    cut = DISCORD_LIMIT - 1 if cut.nil? || cut.zero?
    pieces << line[0..cut]     # up to and including the space
    line = line[(cut + 1)..]
  end
  pieces << line
end
