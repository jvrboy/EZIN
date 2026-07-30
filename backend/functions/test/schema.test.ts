import { describe, expect, it } from "vitest";

describe("backend function package", () => {
  it("uses Node 20 compatible module metadata", async () => {
    const pkg = await import("../package.json");
    expect(pkg.default.engines.node).toBe("20");
    expect(pkg.default.scripts.build).toContain("tsc");
  });
});
