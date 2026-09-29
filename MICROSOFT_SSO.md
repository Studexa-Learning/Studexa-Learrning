# Microsoft 365 Education SSO

Studexa's production identity model is:

- **School admin**: separate Studexa admin account activated with a one-time code.
- **Teachers / students**: may use Microsoft organisational sign-in when the school has been approved for Microsoft SSO.

Recommended implementation: Supabase Auth with the Azure/Microsoft provider. Store the approved school domain and (ideally) Microsoft tenant ID on the `schools` record, then validate the returned identity server-side before creating/linking a profile.

Never trust a browser-supplied domain alone. Do not put Microsoft client secrets, Supabase service-role keys, or MIS credentials in frontend JavaScript.

Typical flow:
1. Platform manager approves the school.
2. School admin enters the organisation domain.
3. Studexa verifies the tenant/domain out-of-band or through the Microsoft identity flow.
4. Teacher/student chooses **Sign in with Microsoft 365**.
5. OAuth callback returns to Studexa.
6. Server/edge function checks tenant/domain and school entitlement, then links the user to the correct school.
