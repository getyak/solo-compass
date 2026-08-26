/** Escape every Telegram MarkdownV2 control character, including backslash. */
export function escapeMarkdown(text: string): string {
  return text.replace(/([_*[\]()~`>#+\-=|{}.!\\])/g, "\\$1");
}
