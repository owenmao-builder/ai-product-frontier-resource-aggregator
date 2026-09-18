export function xinzhiyuanPublishedAt(post: { date: string; date_gmt?: string }): Date | null {
  // WordPress date is site-local; date_gmt is UTC, but neither includes an offset.
  for (const [raw, offset] of [[post.date_gmt, 'Z'], [post.date, '+08:00']]) {
    if (!raw || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?$/.test(raw)) continue;
    const date = new Date(/(?:Z|[+-]\d{2}:\d{2})$/.test(raw) ? raw : raw + offset);
    if (Number.isFinite(date.getTime())) return date;
  }
  return null;
}
