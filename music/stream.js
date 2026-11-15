import { spawn } from "node:child_process";
import { PassThrough } from "node:stream";

// Starts yt-dlp (downloads the audio of a page) and ffmpeg (converts it to
// Ogg/Opus, which Discord can play). Returns a Readable stream of the audio.
//
// A "pipe" connects one program's output to the next program's input:
//   yt-dlp output  ->  ffmpeg input,   ffmpeg output  ->  the stream we return.
// If either program fails, the returned stream is destroyed with an error.
// When the stream is closed (song ended or stopped), both programs are stopped.
export function openStream(url) {
  const output = new PassThrough();

  const ytdlp = spawn("yt-dlp", ytdlpArgs(url), { stdio: ["ignore", "pipe", "pipe"] });
  const ffmpeg = spawn(
    "ffmpeg",
    ["-loglevel", "error", "-i", "pipe:0", "-c:a", "libopus", "-b:a", "128k", "-f", "ogg", "pipe:1"],
    { stdio: ["pipe", "pipe", "pipe"] }
  );

  watchProgram(ytdlp, "yt-dlp", output);
  watchProgram(ffmpeg, "ffmpeg", output);

  ytdlp.stdout.pipe(ffmpeg.stdin);
  // ffmpeg may close its input early (e.g. when we stop); ignore that error.
  ffmpeg.stdin.on("error", () => {});
  ffmpeg.stdout.pipe(output);

  output.on("close", () => {
    stopProgram(ytdlp);
    stopProgram(ffmpeg);
  });

  return output;
}

// The arguments for yt-dlp. "--" means "no more options after this", so a url
// that starts with a dash is still read as a url and not as an option.
export function ytdlpArgs(url) {
  return ["--js-runtimes", "node", "-f", "bestaudio", "-o", "-", "--no-playlist", "--", url];
}

// Stops a program we started:
// - closes our end of its output pipe, so nothing keeps waiting on it;
// - kills it, unless it has already ended.
// On Windows, yt-dlp is a small launcher that starts the real yt-dlp as a
// second process, and kill() only stops the launcher. So there we ask
// Windows' "taskkill" to kill the whole tree (/T) by force (/F).
// `platform` and `spawnProgram` are only replaced in tests.
export function stopProgram(child, platform = process.platform, spawnProgram = spawn) {
  child.stdout?.destroy();
  if (child.exitCode !== null || child.signalCode !== null) return; // already ended

  const treeKill = treeKillCommand(child.pid, platform);
  if (treeKill) {
    runAndIgnoreErrors(spawnProgram, treeKill);
  } else {
    child.kill();
  }
}

// The command that kills a program and everything it started, or null
// when plain kill() is enough (everywhere except Windows).
export function treeKillCommand(pid, platform) {
  if (platform !== "win32" || !pid) return null;
  return ["taskkill", ["/pid", String(pid), "/T", "/F"]];
}

// Starts a helper program (no shell) and ignores it if it cannot start or fails.
function runAndIgnoreErrors(spawnProgram, [command, args]) {
  try {
    const helper = spawnProgram(command, args, { stdio: "ignore", windowsHide: true });
    helper.on("error", () => {});
  } catch {
    // nothing to do: the program may already be gone
  }
}

// Destroys `output` with a short error if the program cannot start
// or exits with an error code.
function watchProgram(child, name, output) {
  let lastError = "";
  child.stderr.on("data", (chunk) => {
    const text = chunk.toString().trim();
    if (text) lastError = text.split("\n").pop();
  });
  child.on("error", (err) => {
    output.destroy(new Error(`${name} could not start: ${err.message}`));
  });
  child.on("close", (code) => {
    if (code !== 0 && code !== null && !output.destroyed) {
      output.destroy(new Error(shortReason(name, code, lastError)));
    }
  });
}

// Makes a short, one-line reason such as "yt-dlp failed: ERROR: Video unavailable".
function shortReason(name, code, lastError) {
  const detail = lastError ? `: ${lastError}` : ` (exit ${code})`;
  return `${name} failed${detail}`.slice(0, 200);
}
