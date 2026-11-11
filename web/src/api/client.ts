// The one place that talks to the bot's web API. Every other file in api/ calls apiRequest.
//
// The bot only answers requests that carry its secret token (see web_api/web_token.rb).
// The first time, the token arrives in the address (?token=...), from the link the bot prints
// in its terminal. We keep it in the browser's storage, so later visits don't need the link.

const TOKEN_KEY = "cake.token";

export type HttpMethod = "GET" | "POST" | "PUT" | "DELETE";

/** What apiRequest throws when the bot says no, or can't be reached at all. */
export class ApiError extends Error {
  /** The HTTP status, e.g. 404. 0 means there was no answer: the bot is off or restarting. */
  status: number;
  /** For a form the bot refused: which fields are wrong, e.g. { MAX_TOOL_ROUNDS: "Must be from 1 to 20." } */
  fieldErrors: Record<string, string> | null;

  constructor(status: number, message: string, fieldErrors: Record<string, string> | null = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.fieldErrors = fieldErrors;
  }
}

export function readToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null; // storage can be blocked (a private window); the page then asks for the link again
  }
}

/** Take ?token=... out of the address and remember it. Call once, when the page starts. */
export function saveTokenFromUrl(): void {
  const address = new URL(window.location.href);
  const token = address.searchParams.get("token");
  if (!token) return;

  try {
    localStorage.setItem(TOKEN_KEY, token);
  } catch {
    // Nothing to do: without storage the token only lives until the page is closed.
  }
  // Remove it from the address bar, so it isn't left in the browser history or a screenshot.
  address.searchParams.delete("token");
  window.history.replaceState(null, "", address.pathname + address.search + address.hash);
}

/**
 * Call the bot's API and get the JSON answer back.
 * <T> is the shape of the answer, e.g. apiRequest<Status>("GET", "/api/status").
 * Throws an ApiError for any answer that is not a success.
 */
export async function apiRequest<T>(method: HttpMethod, path: string, body?: unknown): Promise<T> {
  const response = await sendRequest(method, path, body);
  const answer = await readJson(response);
  if (!response.ok) throw errorFromAnswer(response.status, answer);
  return answer as T;
}

async function sendRequest(method: HttpMethod, path: string, body: unknown): Promise<Response> {
  const headers: Record<string, string> = { "X-Cake-Token": readToken() ?? "" };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  try {
    return await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, "Can't reach the bot."); // fetch itself failed: no connection
  }
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null; // not JSON (should not happen, the API always answers with JSON)
  }
}

// The API answers errors as { error: "..." }, or { errors: { FIELD: "..." } } for a refused form.
function errorFromAnswer(status: number, answer: unknown): ApiError {
  const details = (answer ?? {}) as { error?: string; errors?: Record<string, string> };
  const message = details.error ?? `The bot answered with an error (${status}).`;
  return new ApiError(status, message, details.errors ?? null);
}
