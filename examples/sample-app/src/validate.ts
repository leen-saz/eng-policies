export const MAX_NOTE_LENGTH = 280;

export type NoteInput = { text: string };

export type ValidationResult = { ok: true; value: NoteInput } | { ok: false; error: string };

/** Validates the body of POST /notes. Pure function, so it is unit tested without any binding. */
export function validateNote(input: unknown): ValidationResult {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return { ok: false, error: "body must be a JSON object" };
  }
  const text = (input as Record<string, unknown>).text;
  if (typeof text !== "string") {
    return { ok: false, error: "text must be a string" };
  }
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return { ok: false, error: "text must not be empty" };
  }
  if (trimmed.length > MAX_NOTE_LENGTH) {
    return { ok: false, error: `text must be at most ${MAX_NOTE_LENGTH} characters` };
  }
  return { ok: true, value: { text: trimmed } };
}
