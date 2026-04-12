-- Add device_token column to profiles for APNs push notifications
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS device_token text;
