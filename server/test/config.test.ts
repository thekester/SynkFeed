import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";

describe("loadConfig", () => {
  it("applies safe defaults", () => {
    const config = loadConfig({
      DATABASE_URL: "postgres://localhost/synkfeed",
      JWT_SECRET: "a-secure-test-secret-that-is-long-enough",
    });
    expect(config.PORT).toBe(3000);
    expect(config.ACCESS_TOKEN_TTL).toBe("15m");
    expect(config.REFRESH_TOKEN_TTL_DAYS).toBe(30);
  });

  it("rejects short signing secrets", () => {
    expect(() =>
      loadConfig({ DATABASE_URL: "postgres://localhost/db", JWT_SECRET: "short" }),
    ).toThrow();
  });
});
