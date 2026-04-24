# Auth Service — Implementation Plan

A draft plan for the new auth service. Please review.

## Overview

The new service handles authentication and session management for the web app. It replaces the legacy middleware and provides OIDC-compatible token issuance.

## Tokens

Tokens expire after 15 minutes. Clients must refresh using the refresh endpoint before expiry.

Refresh tokens are stored in a secure HTTP-only cookie and live for 30 days.

### Token format

```
HS256 JWT
payload: { sub, iat, exp, aud, scope }
```

### Revocation

Tokens can be revoked by posting to `/revoke`. Revocations are persisted in Redis with TTL matching the token lifetime.

## Sessions

Sessions persist across restarts and are keyed by refresh-token family. Each session tracks the originating IP and user-agent.

Rotating a refresh token mints a new session and invalidates the prior one.

## Storage

All tokens are persisted in Postgres. Refresh tokens are hashed with argon2id before storage. Sessions live in Redis for read-heavy access and are write-through to Postgres.

### Migration

The migration script is idempotent and can be run multiple times. It backfills the session table from the existing `auth_events` log.

## Open questions

- Should we support passkeys in the same service or a separate issuer?
- TTL of 15 min — is that aligned with the mobile refresh cadence?
