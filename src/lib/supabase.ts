import { createClient, type SupabaseClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const key = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();
export const configured = Boolean(url && key);
export const client: SupabaseClient | null = configured ? createClient(url!, key!, {
 auth: { detectSessionInUrl: true, persistSession: true, autoRefreshToken: true }
}) : null;
export async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
 if (!client) throw new Error('Falta configurar o Supabase. Consulte SETUP.md.');
 const { data, error } = await client.rpc(name, params);
 if (error) throw new Error(error.message);
 return data as T;
}
export async function selectRows<T>(table: string, filter?: {column:string; value:string}): Promise<T[]> {
 if (!client) return [];
 let q = client.from(table).select('*');
 if (filter) q = q.eq(filter.column, filter.value);
 const {data,error} = await q;
 if (error) throw new Error(error.message);
 return (data || []) as T[];
}
