import { lookup } from "node:dns/promises";
import { lookup as systemLookup } from "node:dns";
import type { LookupFunction } from "node:net";
import ipaddr from "ipaddr.js";
import { Agent, fetch, type Response as UndiciResponse } from "undici";

const allowedRanges = new Set(["unicast"]);

export function assertPublicAddress(address: string): void {
  const parsed = ipaddr.parse(address);
  const ipv6 = parsed.kind() === "ipv6" ? (parsed as ipaddr.IPv6) : null;
  const normalized = ipv6?.isIPv4MappedAddress() === true ? ipv6.toIPv4Address() : parsed;
  if (!allowedRanges.has(normalized.range())) {
    throw new Error("blocked_private_address");
  }
}

export async function assertPublicUrl(url: URL): Promise<void> {
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("unsupported_url_scheme");
  }
  if (url.username !== "" || url.password !== "") {
    throw new Error("url_credentials_not_allowed");
  }
  const addresses = await lookup(url.hostname, { all: true, verbatim: true });
  if (addresses.length === 0) throw new Error("dns_resolution_failed");
  for (const address of addresses) assertPublicAddress(address.address);
}

export async function safeFetch(
  initialUrl: string,
  options: {
    headers?: Record<string, string>;
    maximumBytes: number;
    timeoutMs?: number;
  },
): Promise<{ response: UndiciResponse; body: string; finalUrl: string }> {
  const dispatcher = new Agent({
    connect: {
      lookup: safeLookup,
      timeout: options.timeoutMs ?? 15_000,
    },
    headersTimeout: options.timeoutMs ?? 15_000,
    bodyTimeout: options.timeoutMs ?? 15_000,
    maxResponseSize: options.maximumBytes,
  });
  try {
    let current = new URL(initialUrl);
    for (let redirects = 0; redirects <= 5; redirects += 1) {
      await assertPublicUrl(current);
      const response = await fetch(current, {
        dispatcher,
        redirect: "manual",
        ...(options.headers === undefined ? {} : { headers: options.headers }),
        signal: AbortSignal.timeout(options.timeoutMs ?? 20_000),
      });
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        await response.body?.cancel();
        if (location === null || redirects === 5) throw new Error("invalid_redirect");
        current = new URL(location, current);
        continue;
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.byteLength > options.maximumBytes) throw new Error("response_too_large");
      return {
        response,
        body: new TextDecoder().decode(bytes),
        finalUrl: current.toString(),
      };
    }
    throw new Error("too_many_redirects");
  } finally {
    await dispatcher.close();
  }
}

const safeLookup: LookupFunction = (hostname, options, callback) => {
  systemLookup(hostname, options, (error, address, family) => {
    if (error !== null) {
      callback(error, address, family);
      return;
    }
    try {
      if (typeof address === "string") {
        assertPublicAddress(address);
      } else {
        for (const item of address) assertPublicAddress(item.address);
      }
      callback(null, address, family);
    } catch (lookupError) {
      callback(
        lookupError instanceof Error ? lookupError : new Error("blocked_private_address"),
        address,
        family,
      );
    }
  });
};
