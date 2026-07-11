import { createHash, randomBytes } from "node:crypto";
import type { PoolClient } from "pg";

export function createRefreshToken(): string {
  return randomBytes(48).toString("base64url");
}

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export async function storeRefreshToken(
  client: PoolClient,
  input: { userId: string; deviceId: string; token: string; expiresAt: Date },
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `INSERT INTO refresh_tokens(user_id, device_id, token_hash, expires_at)
     VALUES ($1, $2, $3, $4) RETURNING id`,
    [input.userId, input.deviceId, hashRefreshToken(input.token), input.expiresAt],
  );
  return result.rows[0]!.id;
}
