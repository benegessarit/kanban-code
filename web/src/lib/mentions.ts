/** Returns the partial @-mention query at the end of `text` when the cursor
 *  is there, or null otherwise. Ports the Swift `activeMentionQuery(in:)`. */
export function activeMentionQuery(text: string): string | null {
  const atIdx = text.lastIndexOf("@");
  if (atIdx === -1) return null;
  const after = text.slice(atIdx + 1);
  for (const c of after) {
    if (!/[a-zA-Z0-9_-]/.test(c)) return null;
  }
  if (atIdx > 0) {
    const prev = text[atIdx - 1];
    if (!/\s|[.,;:!?]/.test(prev)) return null;
  }
  return after;
}

export function filteredMentionMatches(query: string, candidates: string[]): string[] {
  const q = query.toLowerCase();
  if (!q) return candidates;
  return candidates.filter((c) => c.toLowerCase().startsWith(q));
}

export function insertMention(text: string, handle: string): string {
  const atIdx = text.lastIndexOf("@");
  if (atIdx === -1) return text;
  return text.slice(0, atIdx) + `@${handle} `;
}
