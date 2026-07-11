import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Database } from "../database/pool.js";
import { authenticate } from "../types.js";

const createSchema = z.object({ feedUrl: z.url().max(2_048) });
const paramsSchema = z.object({ id: z.uuid() });
const updateSchema = z
  .object({
    customTitle: z.string().trim().min(1).max(200).nullable().optional(),
    isMuted: z.boolean().optional(),
  })
  .refine((value) => value.customTitle !== undefined || value.isMuted !== undefined);

export function registerSubscriptionRoutes(app: FastifyInstance, database: Database): void {
  app.get("/v1/subscriptions", { preHandler: authenticate }, async (request) => {
    const result = await database.query(
      `SELECT s.id, s.custom_title AS "customTitle", s.is_muted AS "isMuted",
              s.logical_version AS "logicalVersion", s.created_at AS "createdAt",
              f.id AS "feedId", f.feed_url AS "feedUrl", f.site_url AS "siteUrl",
              f.title, f.description
       FROM subscriptions s JOIN feeds f ON f.id = s.feed_id
       WHERE s.user_id = $1 AND s.deleted_at IS NULL ORDER BY s.created_at`,
      [request.user.sub],
    );
    return { subscriptions: result.rows };
  });

  app.post("/v1/subscriptions", { preHandler: authenticate }, async (request, reply) => {
    const input = createSchema.parse(request.body);
    const feedUrl = normalizeFeedUrl(input.feedUrl);
    const title = new URL(feedUrl).hostname;
    const subscription = await database.transaction(async (client) => {
      const feed = await client.query<{ id: string }>(
        `INSERT INTO feeds(canonical_url, feed_url, title)
         VALUES ($1, $1, $2)
         ON CONFLICT(feed_url) DO UPDATE SET feed_url = excluded.feed_url
         RETURNING id`,
        [feedUrl, title],
      );
      const result = await client.query<{ id: string; feed_id: string }>(
        `INSERT INTO subscriptions(id, user_id, feed_id)
         VALUES (gen_random_uuid(), $1, $2)
         ON CONFLICT(user_id, feed_id) DO UPDATE SET
           deleted_at = NULL, updated_at = now(), logical_version = subscriptions.logical_version + 1
         RETURNING id, feed_id`,
        [request.user.sub, feed.rows[0]!.id],
      );
      const row = result.rows[0]!;
      await appendChange(client, request.user.sub, row.id, "subscription_added", {
        id: row.id,
        feedId: row.feed_id,
        feedUrl,
      });
      return { id: row.id, feedId: row.feed_id, feedUrl };
    });
    return reply.code(201).send(subscription);
  });

  app.patch("/v1/subscriptions/:id", { preHandler: authenticate }, async (request, reply) => {
    const { id } = paramsSchema.parse(request.params);
    const input = updateSchema.parse(request.body);
    const result = await database.transaction(async (client) => {
      const updated = await client.query<{
        id: string;
        custom_title: string | null;
        is_muted: boolean;
        logical_version: string;
      }>(
        `UPDATE subscriptions SET
           custom_title = CASE WHEN $1 THEN $2 ELSE custom_title END,
           is_muted = CASE WHEN $3 THEN $4 ELSE is_muted END,
           logical_version = logical_version + 1,
           updated_at = now()
         WHERE id = $5 AND user_id = $6 AND deleted_at IS NULL
         RETURNING id, custom_title, is_muted, logical_version`,
        [
          input.customTitle !== undefined,
          input.customTitle ?? null,
          input.isMuted !== undefined,
          input.isMuted ?? false,
          id,
          request.user.sub,
        ],
      );
      const row = updated.rows[0];
      if (row === undefined) return null;
      await appendChange(client, request.user.sub, id, "subscription_updated", row);
      return row;
    });
    if (result === null) return reply.code(404).send({ code: "subscription_not_found" });
    return result;
  });

  app.delete("/v1/subscriptions/:id", { preHandler: authenticate }, async (request, reply) => {
    const { id } = paramsSchema.parse(request.params);
    const removed = await database.transaction(async (client) => {
      const result = await client.query(
        `UPDATE subscriptions SET deleted_at = now(), updated_at = now(),
           logical_version = logical_version + 1
         WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL RETURNING id`,
        [id, request.user.sub],
      );
      if (result.rowCount === 0) return false;
      await appendChange(client, request.user.sub, id, "subscription_deleted", { id });
      return true;
    });
    if (!removed) return reply.code(404).send({ code: "subscription_not_found" });
    return reply.code(204).send();
  });
}

function normalizeFeedUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new z.ZodError([
      { code: "custom", path: ["feedUrl"], message: "Only HTTP(S) feed URLs are supported" },
    ]);
  }
  url.hash = "";
  return url.toString();
}

async function appendChange(
  client: import("pg").PoolClient,
  userId: string,
  entityId: string,
  operationType: string,
  data: unknown,
): Promise<void> {
  await client.query(
    `INSERT INTO change_log(user_id, entity_type, entity_id, operation_type, data)
     VALUES ($1, 'subscription', $2, $3, $4)`,
    [userId, entityId, operationType, JSON.stringify(data)],
  );
}
