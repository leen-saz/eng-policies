import { describe, expect, it } from "vitest";
import { MAX_NOTE_LENGTH, validateNote } from "../../src/validate";

describe("validateNote", () => {
  it("accepts and trims a normal note", () => {
    expect(validateNote({ text: "  hello  " })).toEqual({ ok: true, value: { text: "hello" } });
  });

  it("rejects non objects", () => {
    for (const bad of [null, undefined, "x", 5, []]) {
      expect(validateNote(bad).ok).toBe(false);
    }
  });

  it("rejects a missing or non string text", () => {
    expect(validateNote({}).ok).toBe(false);
    expect(validateNote({ text: 5 }).ok).toBe(false);
  });

  it("rejects empty and whitespace only text", () => {
    expect(validateNote({ text: "" }).ok).toBe(false);
    expect(validateNote({ text: "   " }).ok).toBe(false);
  });

  it("enforces the length limit on the trimmed value (edge case)", () => {
    expect(validateNote({ text: "a".repeat(MAX_NOTE_LENGTH) }).ok).toBe(true);
    expect(validateNote({ text: "a".repeat(MAX_NOTE_LENGTH + 1) }).ok).toBe(false);
    expect(validateNote({ text: ` ${"a".repeat(MAX_NOTE_LENGTH)} ` }).ok).toBe(true);
  });
});
