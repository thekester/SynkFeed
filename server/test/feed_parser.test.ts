import { describe, expect, it } from "vitest";
import { parseFeed } from "../src/workers/feed_parser.js";
import { assertPublicAddress } from "../src/workers/safe_fetch.js";

describe("feed collector", () => {
  it("parses RSS articles", () => {
    const feed = parseFeed(
      `<rss><channel><title>News</title><item><guid>one</guid><title>First</title><link>https://example.com/one</link></item></channel></rss>`,
      "https://example.com/feed.xml",
    );
    expect(feed.title).toBe("News");
    expect(feed.articles[0]?.externalId).toBe("one");
  });

  it.each(["127.0.0.1", "10.0.0.1", "169.254.169.254", "::1", "fc00::1"])(
    "blocks private or local address %s",
    (address) => expect(() => assertPublicAddress(address)).toThrow("blocked_private_address"),
  );
});
