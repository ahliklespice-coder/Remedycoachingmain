const Stripe = require('stripe');

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);

// Server-side map from plan name -> Stripe Price id. Keeping this on the
// server means the client can never submit an arbitrary price.
const PRICE_IDS = {
  professional: process.env.STRIPE_PRICE_PROFESSIONAL,
  elite: process.env.STRIPE_PRICE_ELITE
};

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { plan, userId, email } = req.body || {};
  const priceId = PRICE_IDS[plan];

  if (!priceId) {
    res.status(400).json({ error: 'Unknown plan' });
    return;
  }
  if (!userId || !email) {
    res.status(400).json({ error: 'userId and email are required' });
    return;
  }

  const origin = req.headers.origin || `https://${req.headers.host}`;

  try {
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      line_items: [{ price: priceId, quantity: 1 }],
      customer_email: email,
      client_reference_id: userId,
      metadata: { user_id: userId, plan },
      subscription_data: { metadata: { user_id: userId, plan } },
      success_url: `${origin}/dashboard.html?billing=success`,
      cancel_url: `${origin}/index.html#pricing`
    });
    res.status(200).json({ url: session.url });
  } catch (err) {
    console.error('create-checkout-session failed', err);
    res.status(500).json({ error: 'Failed to create checkout session' });
  }
};
