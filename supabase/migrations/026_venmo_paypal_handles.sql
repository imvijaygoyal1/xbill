-- Migration 026: Add venmo_handle and paypal_email columns to profiles.
-- These store user payment handles so PaymentLinkService can generate real deep-links.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS venmo_handle text,
  ADD COLUMN IF NOT EXISTS paypal_email  text;
