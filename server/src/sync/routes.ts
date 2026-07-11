import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { z } from "zod";
import type { Database } from "../database/pool.js";
import { authenticate } from "../types.js";

const operationSchema = z.object({
  operationId: z.string().min(1).max(200),
  deviceId: z.uuid(),
  clientSequence: z.number().int().positive(),
  entityType: z.literal("article_state"),
  entityId: z.uuid(),
  operationType: z.enum(["mark_read", "toggle_star"]),
  payload: z.record(z.string(), z.unknown()),
  createdAt: z.iso.datetime(),
});
const pushSchema = z.object({ operations: z.array(operationSchema).max(500) });
const pullSchema = z.object({
  cursor: z.coerce.number().int().nonnegative().default(0),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

export function registerSyncRoutes(app: FastifyInstance, database: Database): void {
  app.post("/v1/sync/push", { preHandler: authenticate }, async (request, reply) => {
    if (!(await deviceIsActive(database, request.user.sub, request.user.deviceId))) {
      return reply.code(403).send({ code: "device_revoked" });
    }
    const input = pushSchema.parse(request.body);
    const result = await database.transaction(async (client) => {
      const acceptedOperations: string[] = [];
      const rejectedOperations: Array<{ operationId: string; code: string }> = [];
      for (const operation of input.operations) {
        if (operation.deviceId !== request.user.deviceId) {
          rejectedOperations.push({ operationId: operation.operationId, code: "device_mismatch" });
          continue;
        }
        const existing = await client.query(
          "SELECT 1 FROM accepted_operations WHERE user_id = $1 AND operation_id = $2",
          [request.user.sub, operation.operationId],
        );
        if (existing.rowCount !== 0) {
          acceptedOperations.push(operation.operationId);
          continue;
        }
        const validationError = await validateArticleStateOperation(client, operation);
        if (validationError !== null) {
          rejectedOperations.push({ operationId: operation.operationId, code: validationError });
          continue;
        }
        const inserted = await client.query(
          `INSERT INTO accepted_operations(
             user_id, operation_id, device_id, client_sequence
           ) VALUES ($1, $2, $3, $4)
           ON CONFLICT DO NOTHING RETURNING operation_id`,
          [request.user.sub, operation.operationId, operation.deviceId, operation.clientSequence],
        );
        if (inserted.rowCount === 0) {
          const duplicate = await client.query(
            "SELECT 1 FROM accepted_operations WHERE user_id = $1 AND operation_id = $2",
            [request.user.sub, operation.operationId],
          );
          if (duplicate.rowCount !== 0) {
            acceptedOperations.push(operation.operationId);
          } else {
            rejectedOperations.push({
              operationId: operation.operationId,
              code: "client_sequence_conflict",
            });
          }
          continue;
        }
        await applyArticleState(client, request.user.sub, operation);
        acceptedOperations.push(operation.operationId);
      }
      return { acceptedOperations, rejectedOperations };
    });
    return result;
  });

  app.get("/v1/sync/pull", { preHandler: authenticate }, async (request, reply) => {
    if (!(await deviceIsActive(database, request.user.sub, request.user.deviceId))) {
      return reply.code(403).send({ code: "device_revoked" });
    }
    const { cursor, limit } = pullSchema.parse(request.query);
    const result = await database.query<{
      cursor: string;
      entity_type: string;
      entity_id: string;
      operation_type: string;
      data: unknown;
    }>(
      `SELECT cursor, entity_type, entity_id, operation_type, data
       FROM change_log WHERE user_id = $1 AND cursor > $2
       ORDER BY cursor LIMIT $3`,
      [request.user.sub, cursor, limit + 1],
    );
    const hasMore = result.rows.length > limit;
    const rows = result.rows.slice(0, limit);
    const nextCursor = rows.length === 0 ? cursor : Number(rows.at(-1)!.cursor);
    await database.query("UPDATE devices SET last_synced_at = now() WHERE id = $1", [
      request.user.deviceId,
    ]);
    return {
      changes: rows.map((row) => ({
        cursor: Number(row.cursor),
        entityType: row.entity_type,
        entityId: row.entity_id,
        operationType: row.operation_type,
        data: row.data,
      })),
      nextCursor,
      hasMore,
    };
  });
}

async function applyArticleState(
  client: PoolClient,
  userId: string,
  operation: z.infer<typeof operationSchema>,
): Promise<void> {
  const isRead = operation.operationType === "mark_read";
  const value = operation.payload[isRead ? "isRead" : "isStarred"] as boolean;
  const state = await client.query<{
    is_read: boolean;
    read_at: Date | null;
    is_starred: boolean;
    starred_at: Date | null;
    is_archived: boolean;
    logical_version: string;
  }>(
    `INSERT INTO article_states(
       user_id, article_id, is_read, read_at, is_starred, starred_at,
       logical_version, updated_at
     ) VALUES (
       $1, $2, $3, CASE WHEN $3 THEN now() ELSE NULL END,
       $4, CASE WHEN $4 THEN now() ELSE NULL END, 1, now()
     )
     ON CONFLICT(user_id, article_id) DO UPDATE SET
       is_read = CASE WHEN $5 THEN $3 ELSE article_states.is_read END,
       read_at = CASE WHEN $5 THEN CASE WHEN $3 THEN now() ELSE NULL END ELSE article_states.read_at END,
       is_starred = CASE WHEN $5 THEN article_states.is_starred ELSE $4 END,
       starred_at = CASE WHEN $5 THEN article_states.starred_at ELSE CASE WHEN $4 THEN now() ELSE NULL END END,
       logical_version = article_states.logical_version + 1,
       updated_at = now()
     RETURNING is_read, read_at, is_starred, starred_at, is_archived, logical_version`,
    [userId, operation.entityId, isRead ? value : false, isRead ? false : value, isRead],
  );
  const data = state.rows[0]!;
  await client.query(
    `INSERT INTO change_log(user_id, entity_type, entity_id, operation_type, data)
     VALUES ($1, 'article_state', $2, $3, $4)`,
    [userId, operation.entityId, operation.operationType, JSON.stringify(data)],
  );
}

async function validateArticleStateOperation(
  client: PoolClient,
  operation: z.infer<typeof operationSchema>,
): Promise<string | null> {
  const value = operation.payload[
    operation.operationType === "mark_read" ? "isRead" : "isStarred"
  ];
  if (typeof value !== "boolean") return "invalid_payload";
  const article = await client.query("SELECT 1 FROM articles WHERE id = $1", [operation.entityId]);
  return article.rowCount === 0 ? "article_not_found" : null;
}

async function deviceIsActive(database: Database, userId: string, deviceId: string): Promise<boolean> {
  const result = await database.query(
    "SELECT 1 FROM devices WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL",
    [deviceId, userId],
  );
  return result.rowCount !== 0;
}
