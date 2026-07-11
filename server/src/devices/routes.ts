import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Database } from "../database/pool.js";
import { authenticate } from "../types.js";

const deviceParams = z.object({ id: z.uuid() });
const renameSchema = z.object({ name: z.string().trim().min(1).max(100) });

export function registerDeviceRoutes(app: FastifyInstance, database: Database): void {
  app.get("/v1/devices", { preHandler: authenticate }, async (request) => {
    const result = await database.query(
      `SELECT id, name, platform, last_synced_at AS "lastSyncedAt",
              revoked_at AS "revokedAt", created_at AS "createdAt"
       FROM devices WHERE user_id = $1 ORDER BY created_at`,
      [request.user.sub],
    );
    return { devices: result.rows };
  });

  app.patch("/v1/devices/:id", { preHandler: authenticate }, async (request, reply) => {
    const { id } = deviceParams.parse(request.params);
    const { name } = renameSchema.parse(request.body);
    const result = await database.query(
      `UPDATE devices SET name = $1 WHERE id = $2 AND user_id = $3 AND revoked_at IS NULL
       RETURNING id, name, platform`,
      [name, id, request.user.sub],
    );
    if (result.rowCount === 0) return reply.code(404).send({ code: "device_not_found" });
    return result.rows[0];
  });

  app.delete("/v1/devices/:id", { preHandler: authenticate }, async (request, reply) => {
    const { id } = deviceParams.parse(request.params);
    const changed = await database.transaction(async (client) => {
      const result = await client.query(
        `UPDATE devices SET revoked_at = now()
         WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL RETURNING id`,
        [id, request.user.sub],
      );
      if (result.rowCount === 0) return false;
      await client.query(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE device_id = $1 AND revoked_at IS NULL",
        [id],
      );
      return true;
    });
    if (!changed) return reply.code(404).send({ code: "device_not_found" });
    return reply.code(204).send();
  });
}
