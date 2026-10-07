const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_USER_ID = process.env.ADMIN_USER_ID;

const svc = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`
};

// Same check as api/admin-credentials.js: re-verify the caller's token with
// Supabase and require it to be the one designated admin account.
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

async function listPendingRequests(res) {
  const reqRes = await fetch(
    `${SUPABASE_URL}/rest/v1/organization_verification_requests?status=eq.pending&select=*&order=created_at.asc`,
    { headers: svc }
  );
  if (!reqRes.ok) {
    res.status(500).json({ error: 'Could not load requests' });
    return;
  }
  const requests = await reqRes.json();

  const orgIds = [...new Set(requests.map((r) => r.organization_id))];
  let orgsById = {};
  if (orgIds.length) {
    const idList = orgIds.map((id) => `"${id}"`).join(',');
    const orgRes = await fetch(
      `${SUPABASE_URL}/rest/v1/organizations?id=in.(${idList})&select=id,organization_name,organization_type,city,state,website,email,verification_status`,
      { headers: svc }
    );
    orgsById = Object.fromEntries((await orgRes.json()).map((o) => [o.id, o]));
  }

  const withUrls = await Promise.all(
    requests.map(async (r) => {
      const documents = await Promise.all(
        (r.document_paths || []).map(async (path) => {
          const signRes = await fetch(
            `${SUPABASE_URL}/storage/v1/object/sign/org-verification/${path}`,
            {
              method: 'POST',
              headers: { ...svc, 'Content-Type': 'application/json' },
              body: JSON.stringify({ expiresIn: 300 })
            }
          );
          const signData = signRes.ok ? await signRes.json() : null;
          return {
            name: path.split('/').pop(),
            url: signData ? `${SUPABASE_URL}/storage/v1${signData.signedURL}` : null
          };
        })
      );
      return { ...r, organization: orgsById[r.organization_id] || null, documents };
    })
  );

  res.status(200).json({ requests: withUrls });
}

async function reviewRequest(req, res) {
  const { requestId, action, reviewerNote } = req.body || {};
  if (!requestId || !['approve', 'reject'].includes(action)) {
    res.status(400).json({ error: 'requestId and a valid action are required' });
    return;
  }

  const found = await fetch(
    `${SUPABASE_URL}/rest/v1/organization_verification_requests?id=eq.${encodeURIComponent(requestId)}&select=id,organization_id,status`,
    { headers: svc }
  );
  const [request] = found.ok ? await found.json() : [];
  if (!request) {
    res.status(404).json({ error: 'Request not found' });
    return;
  }
  if (request.status !== 'pending') {
    res.status(409).json({ error: 'Request was already reviewed' });
    return;
  }

  const approved = action === 'approve';
  const patchRequest = await fetch(
    `${SUPABASE_URL}/rest/v1/organization_verification_requests?id=eq.${encodeURIComponent(requestId)}`,
    {
      method: 'PATCH',
      headers: { ...svc, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        status: approved ? 'approved' : 'rejected',
        reviewer_note: reviewerNote || null,
        reviewed_at: new Date().toISOString()
      })
    }
  );
  if (!patchRequest.ok) {
    res.status(500).json({ error: 'Could not update the request' });
    return;
  }

  // The service role isn't 'authenticated', so the organizations trigger that
  // protects verification_status lets this write through.
  const patchOrg = await fetch(
    `${SUPABASE_URL}/rest/v1/organizations?id=eq.${request.organization_id}`,
    {
      method: 'PATCH',
      headers: { ...svc, 'Content-Type': 'application/json' },
      body: JSON.stringify({ verification_status: approved ? 'verified' : 'rejected' })
    }
  );
  if (!patchOrg.ok) {
    res.status(500).json({ error: 'Request saved but the organization could not be updated' });
    return;
  }

  res.status(200).json({ ok: true });
}

module.exports = async (req, res) => {
  const admin = await requireAdmin(req);
  if (!admin) {
    res.status(403).json({ error: 'Not authorized' });
    return;
  }

  if (req.method === 'GET') {
    await listPendingRequests(res);
  } else if (req.method === 'POST') {
    await reviewRequest(req, res);
  } else {
    res.status(405).json({ error: 'Method not allowed' });
  }
};
