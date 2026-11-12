import { afterEach, describe, expect, it, vi } from "vitest";
import { newIdempotencyKey } from "./uuid";

afterEach(() => vi.unstubAllGlobals());

describe("idempotency keys", () => {
  it("uses the browser UUID API when available", () => {
    const uuid = "b07b3b91-21b8-4a56-a8ee-fc6824f71292";
    vi.stubGlobal("crypto", { randomUUID: () => uuid });
    expect(newIdempotencyKey()).toBe(uuid);
  });

  it("creates distinct v4 UUIDs on HTTP without randomUUID", () => {
    let counter = 0;
    vi.stubGlobal("crypto", {
      getRandomValues: (bytes) => bytes.fill(++counter),
    });
    const first = newIdempotencyKey();
    const second = newIdempotencyKey();
    const v4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    expect(first).toMatch(v4);
    expect(second).toMatch(v4);
    expect(first).not.toBe(second);
  });
});
