# Error Code Contract

This document defines the API error envelope and the most common error codes used by CMS v1.

## Error Envelope

All non-success responses use this shape:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_body",
    "message": "Invalid JSON body",
    "details": {}
  }
}
```

Contract rules:

- `ok` is always `false` for error responses.
- `error.code` is the machine-stable identifier clients should branch on.
- `error.message` is human-readable and may evolve for clarity.
- `error.details` is optional and endpoint-specific.

## Common Codes By Status

### 400 Bad Request

- `invalid_body`: malformed JSON or unsupported payload shape.
- `invalid_id`: route parameter is not a positive integer.
- `invalid_limit`, `invalid_offset`: pagination inputs are invalid.
- `invalid_fields`: sparse-field selection contains unsupported fields.
- `invalid_type_key`, `invalid_taxonomy_key`, `invalid_workspace_key`, `invalid_tenant_key`: invalid key format.
- `invalid_slug`, `invalid_slug_params`: invalid slug input.
- `invalid_term_ids`, `invalid_term_id`, `invalid_taxonomy_scope`: invalid taxonomy term inputs.
- `invalid_expires_at`, `invalid_token`, `invalid_token_id`: token input validation failures.
- `unsupported_cursor_sort`: cursor pagination requested with unsupported sort field.

### 401 Unauthorized

- `unauthorized`: bearer token missing/invalid/expired or bootstrap token policy denies usage.

### 403 Forbidden

- `tenant_scope_denied`: request is outside tenant/workspace scope.
- `system_type`, `system_taxonomy`, `system_role`: protected system resources cannot be modified.

### 404 Not Found

- `not_found`: generic missing resource.
- `content_type_not_found`, `term_not_found`, `tenant_not_found`, `revision_not_found`, `role_not_found`: domain-specific not found variants.
- Anonymous entry detail and slug lookups return `not_found` for draft, scheduled, and archived entries to avoid disclosing editorial state.

### 409 Conflict

- `create_failed`: duplicate key/create conflict.
- `idempotency_conflict`: same idempotency key with different payload.
- `idempotency_in_progress`: idempotent request currently in-flight.
- `entry_locked`, `invalid_lock_token`: lock ownership/lock token conflict.
- `rotate_failed`: token rotation conflict.
- `tenant_inactive`, `tenant_limit_reached`, `workspace_limit_reached`: tenancy policy conflicts.

### 429 Too Many Requests

- `rate_limited`: request exceeded rate limit policy.

### 500 Internal Server Error

- `db_query_failed`, `db_write_failed`: persistence failures.
- `load_failed`, `update_failed`, `delete_failed`, `restore_failed`: post-write/readback failures.
- `idempotency_lookup_failed`, `idempotency_unavailable`: idempotency subsystem failures.
- `scheduler_failed`, `token_create_runtime_error`, `activate_failed`: operation-specific runtime failures.

## Response Consistency Notes

- Validation failures should prefer `400` with a specific `invalid_*` code.
- Authn/authz failures should use `401` or `403` (not `500`).
- Duplicate or replay-shape mismatches should use `409`.
- All rate-limit denials should use `429` + `rate_limited`.

## Representative Examples

Invalid request body:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_body",
    "message": "Invalid JSON body"
  }
}
```

Idempotency conflict:

```json
{
  "ok": false,
  "error": {
    "code": "idempotency_conflict",
    "message": "Idempotency key reused with different request payload"
  }
}
```

Rate limit denial:

```json
{
  "ok": false,
  "error": {
    "code": "rate_limited",
    "message": "Rate limit exceeded",
    "details": {
      "limit": 180,
      "window_sec": 60
    }
  }
}
```
