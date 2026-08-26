import assert from "node:assert/strict";
import test from "node:test";

import { escapeMarkdown } from "./markdown.js";

test("escapes every Telegram MarkdownV2 control character", () => {
  for (const character of "\\_*[]()~`>#+-=|{}.!") {
    assert.equal(escapeMarkdown(character), `\\${character}`);
  }
});

test("preserves ordinary text", () => {
  assert.equal(escapeMarkdown("Chiang Mai 123"), "Chiang Mai 123");
});
