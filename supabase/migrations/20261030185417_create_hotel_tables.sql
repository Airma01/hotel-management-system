
-- =====================================================
-- HOTEL MANAGEMENT SYSTEM
-- INITIAL DATABASE MIGRATION
-- PostgreSQL / Supabase
-- =====================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- =====================================================
-- 2. PROFILES
-- Connected to Supabase Authentication
-- =====================================================

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(30),
    avatar_url TEXT,
    role VARCHAR(20) NOT NULL DEFAULT 'customer'
        CHECK (role IN ('admin', 'receptionist', 'customer')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- Automatically create a profile when a user registers
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, email)
    VALUES (
        NEW.id,
        COALESCE(
            NEW.raw_user_meta_data ->> 'full_name',
            'New Customer'
        ),
        NEW.email
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- 3. ROOM TYPES
-- =====================================================

CREATE TABLE public.room_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    base_price NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
    capacity INTEGER NOT NULL DEFAULT 2 CHECK (capacity > 0),
    amenities JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 4. ROOMS
-- =====================================================

CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number VARCHAR(20) NOT NULL UNIQUE,
    room_type_id UUID NOT NULL REFERENCES public.room_types(id),
    floor_number INTEGER,
    description TEXT,
    max_occupancy INTEGER NOT NULL DEFAULT 2
        CHECK (max_occupancy > 0),
    price_per_night NUMERIC(12,2) NOT NULL
        CHECK (price_per_night >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'available'
        CHECK (status IN (
            'available',
            'maintenance',
            'inactive'
        )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 5. ROOM IMAGES
-- Image files are stored in Supabase Storage.
-- This table stores their paths and metadata.
-- =====================================================

CREATE TABLE public.room_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL
        REFERENCES public.rooms(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL UNIQUE,
    alt_text TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_cover BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_by UUID REFERENCES public.profiles(id)
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX one_cover_image_per_room
ON public.room_images(room_id)
WHERE is_cover = TRUE;

CREATE INDEX idx_room_images_room
ON public.room_images(room_id);


-- =====================================================
-- 6. BOOKINGS
-- =====================================================

CREATE TABLE public.bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    booking_reference VARCHAR(30) NOT NULL UNIQUE,

    customer_id UUID NOT NULL
        REFERENCES public.profiles(id),

    room_id UUID NOT NULL
        REFERENCES public.rooms(id),

    check_in DATE NOT NULL,
    check_out DATE NOT NULL,

    adults INTEGER NOT NULL DEFAULT 1 CHECK (adults > 0),
    children INTEGER NOT NULL DEFAULT 0 CHECK (children >= 0),

    nights INTEGER GENERATED ALWAYS AS
        (check_out - check_in) STORED,

    price_per_night NUMERIC(12,2) NOT NULL
        CHECK (price_per_night >= 0),

    total_price NUMERIC(12,2) NOT NULL
        CHECK (total_price >= 0),

    special_requests TEXT,

    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'confirmed',
            'checked_in',
            'checked_out',
            'cancelled',
            'rejected'
        )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (check_out > check_in)
);


-- Prevent overlapping active reservations.
-- Checkout date is excluded from occupied nights.

ALTER TABLE public.bookings
ADD CONSTRAINT prevent_double_booking
EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
)
WHERE (
    status IN ('pending', 'confirmed', 'checked_in')
);

CREATE INDEX idx_bookings_customer
ON public.bookings(customer_id);

CREATE INDEX idx_bookings_room
ON public.bookings(room_id);

CREATE INDEX idx_bookings_dates
ON public.bookings(check_in, check_out);

CREATE INDEX idx_bookings_status
ON public.bookings(status);


-- =====================================================
-- 7. PAYMENTS
-- =====================================================

CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    booking_id UUID NOT NULL
        REFERENCES public.bookings(id),

    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),

    payment_method VARCHAR(30) NOT NULL
        CHECK (payment_method IN (
            'cash',
            'bank_transfer',
            'card',
            'mobile_money'
        )),

    transaction_reference VARCHAR(150),

    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'completed',
            'failed',
            'refunded'
        )),

    paid_at TIMESTAMPTZ,

    received_by UUID REFERENCES public.profiles(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_booking
ON public.payments(booking_id);


-- =====================================================
-- 8. INVOICES
-- =====================================================

CREATE TABLE public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_number VARCHAR(40) NOT NULL UNIQUE,

    booking_id UUID NOT NULL UNIQUE
        REFERENCES public.bookings(id),

    subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(12,2) NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'unpaid'
        CHECK (status IN (
            'unpaid',
            'partially_paid',
            'paid',
            'cancelled'
        )),

    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date DATE
);


-- =====================================================
-- 9. HOTEL SERVICES
-- =====================================================

CREATE TABLE public.services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(120) NOT NULL UNIQUE,

    description TEXT,

    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),

    image_path TEXT,

    is_available BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 10. BOOKING SERVICES
-- =====================================================

CREATE TABLE public.booking_services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    booking_id UUID NOT NULL
        REFERENCES public.bookings(id) ON DELETE CASCADE,

    service_id UUID NOT NULL
        REFERENCES public.services(id),

    quantity INTEGER NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 11. CUSTOMER REVIEWS
-- =====================================================

CREATE TABLE public.reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    booking_id UUID NOT NULL UNIQUE
        REFERENCES public.bookings(id) ON DELETE CASCADE,

    customer_id UUID NOT NULL
        REFERENCES public.profiles(id),

    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),

    comment TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 12. HOTEL SETTINGS
-- =====================================================

CREATE TABLE public.hotel_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    hotel_name VARCHAR(150) NOT NULL,
    description TEXT,
    address TEXT,
    phone VARCHAR(30),
    email VARCHAR(255),
    logo_path TEXT,
    currency VARCHAR(3) NOT NULL DEFAULT 'ETB',
    tax_percentage NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (tax_percentage BETWEEN 0 AND 100),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =====================================================
-- 13. UPDATED_AT TRIGGER
-- =====================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER room_types_updated_at
BEFORE UPDATE ON public.room_types
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER rooms_updated_at
BEFORE UPDATE ON public.rooms
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER bookings_updated_at
BEFORE UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================
-- 14. STORAGE BUCKETS
-- =====================================================

INSERT INTO storage.buckets (
    id, name, public, file_size_limit, allowed_mime_types
)
VALUES (
    'room-images',
    'room-images',
    TRUE,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
),
(
    'hotel-images',
    'hotel-images',
    TRUE,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
);


-- =====================================================
-- END OF INITIAL DATABASE MIGRATION
-- =====================================================

-- =====================================================
-- 15. DATABASE SECURITY (RLS)
-- =====================================================

CREATE OR REPLACE FUNCTION public.is_hotel_staff()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = (SELECT auth.uid())
          AND role IN ('admin', 'receptionist')
          AND is_active = TRUE
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_hotel_staff()
TO authenticated;

-- Enable RLS on all application tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hotel_settings ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY "Users view their own profile or staff views all"
ON public.profiles FOR SELECT TO authenticated
USING (id = (SELECT auth.uid()) OR public.is_hotel_staff());

CREATE POLICY "Staff manage profiles"
ON public.profiles FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Room types
CREATE POLICY "Public view active room types"
ON public.room_types FOR SELECT TO anon, authenticated
USING (is_active = TRUE OR public.is_hotel_staff());

CREATE POLICY "Staff manage room types"
ON public.room_types FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Rooms
CREATE POLICY "Public view available rooms"
ON public.rooms FOR SELECT TO anon, authenticated
USING (status = 'available' OR public.is_hotel_staff());

CREATE POLICY "Staff manage rooms"
ON public.rooms FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Room images
CREATE POLICY "Public view room images"
ON public.room_images FOR SELECT TO anon, authenticated
USING (TRUE);

CREATE POLICY "Staff manage room images"
ON public.room_images FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Bookings
CREATE POLICY "Customers view own bookings"
ON public.bookings FOR SELECT TO authenticated
USING (
    customer_id = (SELECT auth.uid())
    OR public.is_hotel_staff()
);

CREATE POLICY "Customers create own bookings"
ON public.bookings FOR INSERT TO authenticated
WITH CHECK (customer_id = (SELECT auth.uid()));

CREATE POLICY "Staff manage bookings"
ON public.bookings FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Payments
CREATE POLICY "Customers view own payments"
ON public.payments FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.bookings b
        WHERE b.id = booking_id
        AND b.customer_id = (SELECT auth.uid())
    )
    OR public.is_hotel_staff()
);

CREATE POLICY "Staff manage payments"
ON public.payments FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Invoices
CREATE POLICY "Customers view own invoices"
ON public.invoices FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.bookings b
        WHERE b.id = booking_id
        AND b.customer_id = (SELECT auth.uid())
    )
    OR public.is_hotel_staff()
);

CREATE POLICY "Staff manage invoices"
ON public.invoices FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Services
CREATE POLICY "Public view available services"
ON public.services FOR SELECT TO anon, authenticated
USING (is_available = TRUE OR public.is_hotel_staff());

CREATE POLICY "Staff manage services"
ON public.services FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Booking services
CREATE POLICY "Customers view own booking services"
ON public.booking_services FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.bookings b
        WHERE b.id = booking_id
        AND b.customer_id = (SELECT auth.uid())
    )
    OR public.is_hotel_staff()
);

CREATE POLICY "Staff manage booking services"
ON public.booking_services FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Reviews
CREATE POLICY "Public view reviews"
ON public.reviews FOR SELECT TO anon, authenticated
USING (TRUE);

CREATE POLICY "Customers create reviews for own bookings"
ON public.reviews FOR INSERT TO authenticated
WITH CHECK (
    customer_id = (SELECT auth.uid())
    AND EXISTS (
        SELECT 1 FROM public.bookings b
        WHERE b.id = booking_id
        AND b.customer_id = (SELECT auth.uid())
        AND b.status = 'checked_out'
    )
);

CREATE POLICY "Staff manage reviews"
ON public.reviews FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Hotel settings
CREATE POLICY "Public view hotel settings"
ON public.hotel_settings FOR SELECT TO anon, authenticated
USING (TRUE);

CREATE POLICY "Staff manage hotel settings"
ON public.hotel_settings FOR ALL TO authenticated
USING (public.is_hotel_staff())
WITH CHECK (public.is_hotel_staff());

-- Storage: public image viewing
CREATE POLICY "Public view hotel images"
ON storage.objects FOR SELECT TO anon, authenticated
USING (bucket_id IN ('room-images', 'hotel-images'));

-- Storage: staff upload
CREATE POLICY "Staff upload hotel images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id IN ('room-images', 'hotel-images')
    AND public.is_hotel_staff()
);

CREATE POLICY "Staff update hotel images"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id IN ('room-images', 'hotel-images')
    AND public.is_hotel_staff()
)
WITH CHECK (
    bucket_id IN ('room-images', 'hotel-images')
    AND public.is_hotel_staff()
);

CREATE POLICY "Staff delete hotel images"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id IN ('room-images', 'hotel-images')
    AND public.is_hotel_staff()
);
