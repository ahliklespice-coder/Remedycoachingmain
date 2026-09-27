const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_USER_ID = process.env.ADMIN_USER_ID;

// Verifies the caller's Supabase access token and confirms it belongs to the
// one designated admin account. Never trust anything the client claims about
// its own identity — always re-check the token against Supabase itself.
async function requireAdmin(req) {
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return null;

  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!res.ok) return null;
  const user = await res.json();
  return user.id === ADMIN_USER_ID ? user : null;
}

async function listPendingCredentials(res) {
  const credRes = await fetch(
    `${SUPABASE_URL}/rest/v1/credentials?status=eq.pending&select=*&order=created_at.asc`,
    { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } }
  );
  const credentials = await credRes.json();

  const coachIds = [...new Set(credentials.map((c) => c.coach_id))];
  let profilesById = {};
  if (coachIds.length) {
    const idList = coachIds.map((id) => `"${id}"`).join(',');
    const profRes = await fetch(
      `${SUPABASE_URL}/rest/v1/profiles?id=in.(${idList})&select=id,name,email,sport`,
      { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } }
    );
    const profiles = await profRes.json();
    profilesById = Object.fromEntries(profiles.map((p) => [p.id, p]));
  }

  const withUrls = await Promise.all(
    credentials.map(async (c) => {
      const signRes = await fetch(
        `${SUPABASE_URL}/storage/v1/object/sign/credentials/${c.file_path}`,
        {
          method: 'POST',
          headers: {
            apikey: SERVICE_KEY,
            Authorization: `Bearer ${SERVICE_KEY}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ expiresIn: 300 })
        }
      );
      const signData = signRes.ok ? await signRes.json() : null;
      return {
        ...c,
        coach: profilesById[c.coach_id] || null,
        file_url: signData ? `${SUPABASE_URL}/storage/v1${signData.signedURL}` : null
      };
    })
  );

  res.status(200).json({ credentials: withUrls });
}

async function reviewCredential(req, res) {
  const { credentialId, action, reviewerNote } = req.body || {};
  if (!credentialId || !['approve', 'reject'].includes(action)) {
    res.status(400).json({ error: 'credentialId and a valid action are required' });
    return;
  }

  const credRes = await fetch(
    `${SUPABASE_URL}/rest/v1/credentials?id=eq.${credentialId}&select=*`,
    { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } }
  );
  const [credential] = await credRes.json();
  if (!credential) {
    res.status(404).json({ error: 'Credential not found' });
    return;
  }

  const newStatus = action === 'approve' ? 'approved' : 'rejected';
  await fetch(`${SUPABASE_URL}/rest/v1/credentials?id=eq.${credentialId}`, {
    method: 'PATCH',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      status: newStatus,
      reviewer_note: reviewerNote || null,
      reviewed_at: new Date().toISOString()
    })
  });

  // Using the service role key here means auth.role() = 'service_role', not
  // 'authenticated' — so the protect_verification_fields trigger (which only
  // blocks ordinary logged-in users) does not block this write.
  await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${credential.coach_id}`, {
    method: 'PATCH',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(
      action === 'approve'
        ? { verified: true, verification_status: 'verified' }
        : { verification_status: 'rejected' }
    )
  });

  res.status(200).json({ ok: true });
}

module.exports = async (req, res) => {
  const admin = await requireAdmin(req);
  if (!admin) {
    res.status(403).json({ error: 'Not authorized' });
    return;
  }

  if (req.method === 'GET') {
    await listPendingCredentials(res);
  } else if (req.method === 'POST') {
    await reviewCredential(req, res);
  } else {
    res.status(405).json({ error: 'Method not allowed' });
  }
};
