import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/integration/**/*.test.ts"],
    environment: "node",
    // The tests share one local D1 database, so files run one at a time.
    fileParallelism: false,
    testTimeout: 30_000,
  },
});
