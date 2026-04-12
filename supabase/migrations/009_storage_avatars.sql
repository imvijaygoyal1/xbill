-- =============================================================================
-- 009_storage_avatars.sql
-- Creates the avatars storage bucket and RLS policies.
-- Avatars are public (readable by anyone) but only the owner can write.
-- =============================================================================

-- Create bucket (idempotent)
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload/update their own avatar
CREATE POLICY "Users can upload their own avatar"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'avatars'
    AND name = (auth.uid()::text || '.jpg')
);

CREATE POLICY "Users can update their own avatar"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'avatars'
    AND name = (auth.uid()::text || '.jpg')
);

-- Allow anyone to read avatars (public bucket)
CREATE POLICY "Avatars are publicly readable"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');
