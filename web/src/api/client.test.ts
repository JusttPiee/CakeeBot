import { afterEach, expect, it, vi } from "vitest";
import { apiRequest, readToken, saveTokenFromUrl } from "./client";

// Replace the browser's fetch with a pretend one that answers with this status and JSON body.
function mockFetch(status: number, body: unknown) {
  const fetchMock = vi.fn(async () => new Response(JSON.stringify(body), { status }));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

it("sends the saved token and parses JSON", async () => {
  localStorage.setItem("cake.token", "abc");
  const fetchMock = mockFetch(200, { bot_name: "Cake" });

  const status = await apiRequest<{ bot_name: string }>("GET", "/api/status");

  expect(status.bot_name).toBe("Cake");
  const [path, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(path).toBe("/api/status");
  expect((options.headers as Record<string, string>)["X-Cake-Token"]).toBe("abc");
});

it("sends the body as JSON", async () => {
  const fetchMock = mockFetch(200, { ok: true });

  await apiRequest("PUT", "/api/config", { values: { MAX_TOOL_ROUNDS: 9 } });

  const [, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(options.method).toBe("PUT");
  expect(options.body).toBe('{"values":{"MAX_TOOL_ROUNDS":9}}');
});

it("turns an error answer into an ApiError with field errors", async () => {
  mockFetch(422, { errors: { MAX_HISTORY_MESSAGES: "must be 10 to 200" } });

  await expect(apiRequest("PUT", "/api/config", {})).rejects.toMatchObject({
    status: 422,
    fieldErrors: { MAX_HISTORY_MESSAGES: "must be 10 to 200" },
  });
});

it("uses the server's message for a plain error", async () => {
  mockFetch(404, { error: "Not found." });

  await expect(apiRequest("GET", "/api/nope")).rejects.toMatchObject({ status: 404, message: "Not found." });
});

it("reports status 0 when the bot cannot be reached", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new TypeError("Failed to fetch"))));

  await expect(apiRequest("GET", "/api/status")).rejects.toMatchObject({ status: 0 });
});

it("moves the token from the URL into storage", () => {
  history.replaceState(null, "", "/memory/people?token=xyz");

  saveTokenFromUrl();

  expect(readToken()).toBe("xyz");
  expect(location.search).toBe("");
  expect(location.pathname).toBe("/memory/people");
});
