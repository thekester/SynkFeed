import argon2 from "argon2";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppConfig } from "../config.js";
import type { Database } from "../database/pool.js";
import { createRefreshToken, hashRefreshToken, storeRefreshToken } from "./tokens.js";

const credentialsSchema = z.object({
  email: z.email().max(320).transform((value) => value.trim().toLowerCase()),
  password: z.string().min(12).max(200),
  deviceName: z.string().trim().min(1).max(100),
  platform: z.enum(["android", "windows", "linux"]),
});
const refreshSchema = z.object({ refreshToken: z.string().min(32).max(512) });

interface AuthRow {
  user_id: string;
  password_hash: string;
  device_id: string;
}

export function registerAuthRoutes(
  app: FastifyInstance,
  database: Database,
  config: AppConfig,
): void {
  app.post("/v1/auth/register", { config: { rateLimit: { max: 5, timeWindow: "1 minute" } } }, async (request, reply) => {
    const input = credentialsSchema.parse(request.body);
    const passwordHash = await argon2.hash(input.password, { type: argon2.argon2id });
    try {
      const session = await database.transaction(async (client) => {
        const user = await client.query<{ id: string }>(
          "INSERT INTO users(email, password_hash) VALUES ($1, $2) RETURNING id",
          [input.email, passwordHash],
        );
        const userId = user.rows[0]!.id;
        const device = await client.query<{ id: string }>(
          `INSERT INTO devices(user_id, name, platform)
           VALUES ($1, $2, $3) RETURNING id`,
          [userId, input.deviceName, input.platform],
        );
        return issueSession(app, client, config, userId, device.rows[0]!.id);
      });
      return reply.code(201).send(publicSession(session));
    } catch (error) {
      if (isUniqueViolation(error)) {
        return reply.code(409).send({ code: "email_already_registered" });
      }
      throw error;
    }
  });

  app.post("/v1/auth/login", { config: { rateLimit: { max: 10, timeWindow: "1 minute" } } }, async (request, reply) => {
    const input = credentialsSchema.parse(request.body);
    const user = await database.query<{ id: string; password_hash: string }>(
      "SELECT id, password_hash FROM users WHERE email = $1 AND deleted_at IS NULL",
      [input.email],
    );
    const row = user.rows[0];
    if (row === undefined || !(await argon2.verify(row.password_hash, input.password))) {
      return reply.code(401).send({ code: "invalid_credentials" });
    }
    const session = await database.transaction(async (client) => {
      const device = await client.query<{ id: string }>(
        `INSERT INTO devices(user_id, name, platform)
         VALUES ($1, $2, $3) RETURNING id`,
        [row.id, input.deviceName, input.platform],
      );
      return issueSession(app, client, config, row.id, device.rows[0]!.id);
    });
    return publicSession(session);
  });

  app.post("/v1/auth/refresh", async (request, reply) => {
    const { refreshToken } = refreshSchema.parse(request.body);
    const result = await database.transaction(async (client) => {
      const token = await client.query<{
        id: string;
        user_id: string;
        device_id: string;
      }>(
        `SELECT rt.id, rt.user_id, rt.device_id
         FROM refresh_tokens rt
         JOIN devices d ON d.id = rt.device_id
         WHERE rt.token_hash = $1 AND rt.revoked_at IS NULL
           AND rt.expires_at > now() AND d.revoked_at IS NULL
         FOR UPDATE`,
        [hashRefreshToken(refreshToken)],
      );
      const current = token.rows[0];
      if (current === undefined) return null;
      const session = await issueSession(
        app,
        client,
        config,
        current.user_id,
        current.device_id,
      );
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now(), replaced_by = $2 WHERE id = $1`,
        [current.id, session.refreshTokenId],
      );
      return session;
    });
    if (result === null) return reply.code(401).send({ code: "invalid_refresh_token" });
    const { refreshTokenId: _, ...session } = result;
    return session;
  });
}

async function issueSession(
  app: FastifyInstance,
  client: import("pg").PoolClient,
  config: AppConfig,
  userId: string,
  deviceId: string,
) {
  const refreshToken = createRefreshToken();
  const expiresAt = new Date(Date.now() + config.REFRESH_TOKEN_TTL_DAYS * 86_400_000);
  const refreshTokenId = await storeRefreshToken(client, {
    userId,
    deviceId,
    token: refreshToken,
    expiresAt,
  });
  return {
    accessToken: app.jwt.sign({ sub: userId, deviceId }, { expiresIn: config.ACCESS_TOKEN_TTL }),
    refreshToken,
    refreshTokenId,
    deviceId,
  };
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "23505";
}

function publicSession(session: Awaited<ReturnType<typeof issueSession>>) {
  const { refreshTokenId: _, ...result } = session;
  return result;
}
