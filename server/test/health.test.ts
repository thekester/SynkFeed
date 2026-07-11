import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import type { Database } from "../src/database/pool.js";

describe("health routes", () => {
  it("reports liveness and database readiness", async () => {
    const close = vi.fn(async () => undefined);
    const database: Database = {
      query: async <T extends QueryResultRow>() =>
        ({ rows: <T[]>[], rowCount: 1 } as QueryResult<T>),
      transaction: async <T>(work: (client: PoolClient) => Promise<T>) =>
        work({} as PoolClient),
      close,
    };
    const app = await buildApp(
      loadConfig({
        NODE_ENV: "test",
        DATABASE_URL: "postgres://localhost/synkfeed",
        JWT_SECRET: "a-secure-test-secret-that-is-long-enough",
      }),
      database,
    );

    const live = await app.inject({ method: "GET", url: "/health/live" });
    const ready = await app.inject({ method: "GET", url: "/health/ready" });

    expect(live.statusCode).toBe(200);
    expect(ready.statusCode).toBe(200);
    expect(ready.json()).toEqual({ status: "ready" });
    await app.close();
    expect(close).toHaveBeenCalledOnce();
  });
});
