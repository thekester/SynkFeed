import type { FastifyReply, FastifyRequest } from "fastify";

export interface AccessToken {
  sub: string;
  deviceId: string;
}

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: AccessToken;
    user: AccessToken;
  }
}

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  try {
    await request.jwtVerify();
  } catch {
    await reply.code(401).send({ code: "unauthorized" });
  }
}
