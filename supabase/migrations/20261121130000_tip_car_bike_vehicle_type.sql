-- Add Bike Taxi while preserving existing Car and Bus ride records.
ALTER TYPE public.vehicle_type ADD VALUE IF NOT EXISTS 'bike';
