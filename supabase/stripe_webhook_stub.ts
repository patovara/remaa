// Stripe webhook stub para siguiente fase.
// Recomendado: desplegar como Edge Function de Supabase o servicio separado.

export async function handleStripeWebhook(request: Request): Promise<Response> {
  const payload = await request.text();

  // TODO:
  // 1) Verificar firma Stripe-Signature
  // 2) Parsear eventos: invoice.paid, invoice.payment_failed, customer.subscription.deleted
  // 3) Persistir en tabla audit_logs o billing_events

  return new Response(
    JSON.stringify({ status: 'stub', received: payload.length > 0 }),
    { headers: { 'Content-Type': 'application/json' }, status: 200 },
  );
}
