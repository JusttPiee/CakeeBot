import { act, renderHook, waitFor } from "@testing-library/react";
import { expect, it, vi } from "vitest";
import { ApiError } from "../api/client";
import { useApi } from "./useApi";

it("goes from loading to data, and reloads on demand", async () => {
  const load = vi.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(2);

  const { result } = renderHook(() => useApi<number>(load, []));

  expect(result.current.loading).toBe(true);
  await waitFor(() => expect(result.current.data).toBe(1));
  expect(result.current.loading).toBe(false);

  act(() => result.current.reload());

  await waitFor(() => expect(result.current.data).toBe(2));
  expect(load).toHaveBeenCalledTimes(2);
});

it("keeps the error when loading fails", async () => {
  const load = vi.fn().mockRejectedValue(new ApiError(500, "boom"));

  const { result } = renderHook(() => useApi<number>(load, []));

  await waitFor(() => expect(result.current.error?.status).toBe(500));
  expect(result.current.data).toBeNull();
  expect(result.current.loading).toBe(false);
});

it("drops the old data when what it depends on changes", async () => {
  const load = vi.fn(async (id: string) => `note of ${id}`);

  const { result, rerender } = renderHook(({ id }) => useApi<string>(() => load(id), [id]), {
    initialProps: { id: "5" },
  });
  await waitFor(() => expect(result.current.data).toBe("note of 5"));

  rerender({ id: "6" });

  expect(result.current.data).toBeNull(); // never show person 5's note under person 6's name
  await waitFor(() => expect(result.current.data).toBe("note of 6"));
});
