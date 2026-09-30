import type { ReviewMetadataMarker } from './types.ts';

export const REVIEW_MARKER_PATTERN = /<!--\s*agentkit-code-review:v1\s+(\{.*?\})\s*-->/s;

export function parseReviewMetadataMarker(
  body: string | null | undefined,
): ReviewMetadataMarker | null {
  if (!body) {
    return null;
  }

  const match = REVIEW_MARKER_PATTERN.exec(body);
  if (!match) {
    return null;
  }

  try {
    const parsed = JSON.parse(match[1]) as Partial<ReviewMetadataMarker>;
    if (
      parsed.schema !== 'agentkit-code-review' ||
      parsed.version !== 1 ||
      typeof parsed.headSha !== 'string' ||
      (parsed.baseSha !== null && typeof parsed.baseSha !== 'string') ||
      (parsed.scope !== 'full' && parsed.scope !== 'incremental' && parsed.scope !== 'manual') ||
      typeof parsed.changedFilesHash !== 'string' ||
      !Array.isArray(parsed.domains) ||
      !parsed.domains.every((domain) => typeof domain === 'string') ||
      typeof parsed.generatedAt !== 'string'
    ) {
      return null;
    }

    return parsed as ReviewMetadataMarker;
  } catch {
    return null;
  }
}
