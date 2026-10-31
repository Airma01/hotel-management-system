import { createClient } from "@supabase/supabase-js/dist/index.cjs";
import dotenv from "dotenv";
dotenv.config();
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
export const adminSupabase = createClient(supabaseUrl, supabaseKey,
    {
        auth:{
        autoRefreshToken: false,
        persistSession: false,
    }
    }
);
export const createUserClient = createClient(supabaseUrl, supabaseKey, {
    auth: {
        autoRefreshToken: true,
        persistSession: true,
    },
    global: {
        headers: {
            Authorization: `Bearer ${supabaseKey}`,
        },
    },

});

;
