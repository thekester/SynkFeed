import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Database } from "../database/pool.js";
import { authenticate } from "../types.js";

const listSchema = z.object({
  feedId: z.uuid().optional(),
  unread: z.stringbool().optional(),
  starred: z.stringbool().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().nonnegative().default(0),
});
const paramsSchema = z.object({ id: z.uuid() });

export function registerArticleRoutes(app: FastifyInstance, database: Database): void {
  app.get("/v1/articles", { preHandler: authenticate }, async (request) => {
    const input = listSchema.parse(request.query);
    const result = await database.query(
      `SELECT a.id, a.feed_id AS "feedId", a.external_id AS "externalId",
              a.canonical_url AS "canonicalUrl", a.title, a.author, a.summary,
              a.published_at AS "publishedAt", COALESCE(s.is_read, false) AS "isRead",
              COALESCE(s.is_starred, false) AS "isStarred"
       FROM articles a
       JOIN subscriptions sub ON sub.feed_id = a.feed_id AND sub.user_id = $1
         AND sub.deleted_at IS NULL
       LEFT JOIN article_states s ON s.article_id = a.id AND s.user_id = $1
       WHERE ($2::uuid IS NULL OR a.feed_id = $2)
         AND ($3::boolean IS NULL OR COALESCE(s.is_read, false) = NOT $3)
         AND ($4::boolean IS NULL OR COALESCE(s.is_starred, false) = $4)
       ORDER BY a.published_at DESC NULLS LAST, a.id LIMIT $5 OFFSET $6`,
      [request.user.sub, input.feedId ?? null, input.unread ?? null, input.starred ?? null, input.limit, input.offset],
    );
    return { articles: result.rows, limit: input.limit, offset: input.offset };
  });

  app.get("/v1/articles/:id", { preHandler: authenticate }, async (request, reply) => {
    const { id } = paramsSchema.parse(request.params);
    const result = await database.query(
      `SELECT a.*, COALESCE(s.is_read, false) AS "isRead",
              COALESCE(s.is_starred, false) AS "isStarred"
       FROM articles a
       JOIN subscriptions sub ON sub.feed_id = a.feed_id AND sub.user_id = $1
         AND sub.deleted_at IS NULL
       LEFT JOIN article_states s ON s.article_id = a.id AND s.user_id = $1
       WHERE a.id = $2`,
      [request.user.sub, id],
    );
    if (result.rowCount === 0) return reply.code(404).send({ code: "article_not_found" });
    return result.rows[0];
  });
}
