-- Add unique constraint so a (user_id, token) pair can never be duplicated.
-- Enables safe upsert in the future and prevents ghost rows from concurrent
-- token refresh calls.

ALTER TABLE public.device_tokens
  ADD CONSTRAINT device_tokens_user_id_token_unique UNIQUE (user_id, token);
