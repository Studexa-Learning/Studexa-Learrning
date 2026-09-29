# Studexa Learning demo build

This ZIP contains the public Studexa Learning site, school request flow, school-admin demo and private Studexa Manager demo. It is a working static prototype using `localStorage` so you can open it without a backend.

## Pages
- `index.html` — public homepage
- `request.html` — school access request
- `login.html` — demo login/activation screen
- `admin.html` — school admin panel
- `manager.html` — private Studexa Manager control room
- `templates/studexa-students-template.csv` — import template
- `supabase/schema.sql` — starter shared database schema
- `supabase/MICROSOFT_SSO.md` — Microsoft Entra/Supabase design

## Demo data
The browser stores demo schools, requests, teachers, students, classes and audit events locally. Submit a school request, then open Studexa Manager and approve it to see a randomly generated activation code.

## Production note
The static demo deliberately does **not** include real email delivery, Microsoft secrets, service-role keys or MIS credentials. Those belong in server-side functions/secrets. Activation tokens should be emailed once and stored only as one-way hashes in the database.
