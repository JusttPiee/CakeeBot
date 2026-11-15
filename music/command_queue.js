// Runs commands one at a time PER GUILD, in the order they arrived.
// Why: "join" takes a moment (it awaits Discord), and Ruby sends "play" right after it.
// If both ran at once, "play" would start before the join finished.
//
// `handler(command)` does the work and may return a promise.
// `onError(command, err)` is called if the handler throws; the queue keeps going.
export function createCommandQueue(handler, onError) {
  // guild id -> the promise of the last command queued for that guild.
  const tails = new Map();

  // Adds a command to the end of its guild's line. Different guilds do not wait for each other.
  function enqueue(command) {
    const previous = tails.get(command.guild) || Promise.resolve();
    const next = previous.then(() => runOne(command));
    tails.set(command.guild, next);
    // Once this command is done, forget the guild unless a newer command was queued after it.
    next.then(() => {
      if (tails.get(command.guild) === next) tails.delete(command.guild);
    });
    return next;
  }

  // Runs one command; an error is reported but never breaks the chain.
  async function runOne(command) {
    try {
      await handler(command);
    } catch (err) {
      onError(command, err);
    }
  }

  return enqueue;
}
