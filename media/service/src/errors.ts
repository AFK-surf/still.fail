// What the service refuses with: a status, a code for programs and words for the member (Chinese: the media app's).

export const STATUS = {
  bad_request: 400,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  too_large: 413,
  unsupported: 415,
  station: 502,
  internal: 500,
} as const;
export type Code = keyof typeof STATUS;

export class MediaError extends Error {
  readonly code: Code;
  readonly status: number;
  constructor(code: Code, message: string, status: number = STATUS[code]) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/// A body the request got wrong (a field missing or of the wrong kind).
export const bad = (message: string) => new MediaError("bad_request", message);
