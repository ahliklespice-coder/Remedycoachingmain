const Stripe = require('stripe');

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const PLAN_BY_PRICE = {
  [process.env.STRIPE_PRICE_PROFESSIONAL]: 'professional',
  [process.env.STRIPE_PRICE_ELITE]: 'elite'
};

function buffer(readable) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    readable.on('data', (chunk) => chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk));
    readable.on('end', () => resolve(Buffer.concat(chunks)));
    readable.on('error', reject);
  });
}

async function upsertSubscription(row) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/subscriptions?on_conflict=user_id`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates'
    },
    body: JSON.stringify(row)
  });
  if (!res.ok) {
    console.error('Supabase upsert failed', res.status, await res.text());
  }
}

async function updateSubscriptionByStripeId(stripeSubscriptionId, patch) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/subscriptions?stripe_subscription_id=eq.${encodeURIComponent(stripeSubscriptionId)}`,
    {
      method: 'PATCH',
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(patch)
    }
  );
  if (!res.ok) {
    console.error('Supabase update failed', res.status, await res.text());
  }
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }

  const sig = req.headers['stripe-signature'];
  let event;
  try {
    const buf = await buffer(req);
    event = stripe.webhooks.constructEvent(buf, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('Webhook signature verification failed', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;
        const userId = session.client_reference_id || session.metadata?.user_id;
        const plan = session.metadata?.plan;
        if (userId && plan) {
          const subscription = await stripe.subscriptions.retrieve(session.subscription);
          await upsertSubscription({
            user_id: userId,
            plan,
            status: 'active',
            stripe_customer_id: session.customer,
            stripe_subscription_id: session.subscription,
            current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
            updated_at: new Date().toISOString()
          });
        }
        break;
      }

      case 'customer.subscription.updated': {
        const sub = event.data.object;
        const priceId = sub.items?.data?.[0]?.price?.id;
        const plan = PLAN_BY_PRICE[priceId] || sub.metadata?.plan || 'professional';
        const status = sub.status === 'active' || sub.status === 'trialing' ? 'active'
          : sub.status === 'past_due' ? 'past_due'
          : 'canceled';
        await updateSubscriptionByStripeId(sub.id, {
          plan,
          status,
          current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
          updated_at: new Date().toISOString()
        });
        break;
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object;
        await updateSubscriptionByStripeId(sub.id, {
          plan: 'free',
          status: 'canceled',
          updated_at: new Date().toISOString()
        });
        break;
      }

      default:
        // Ignore anything else.
        break;
    }
    res.status(200).json({ received: true });
  } catch (err) {
    console.error('Webhook handling failed', err);
    res.status(500).json({ error: 'Webhook handler failed' });
  }
};

module.exports.config = { api: { bodyParser: false } };
