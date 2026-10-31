import test from "node:test";
import assert from "node:assert/strict";

test("node tests run from the web subfolder", () => {
  assert.equal(1 + 1, 2);
});
