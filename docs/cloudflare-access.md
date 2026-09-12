# Cloudflare Access and MFA

Protect only `https://<VAULTWARDEN_DOMAIN>/admin` with interactive Cloudflare Access. Do not put the complete Vaultwarden hostname behind an interactive Access login until every Bitwarden client you use has been tested: desktop and mobile applications may not support Access's browser redirect login for API calls.

Cloudflare Access and Vaultwarden's `ADMIN_TOKEN` are independent protections.

## Enable a Login Method

For a personal deployment, use Cloudflare One-time PIN:

1. In Cloudflare, select **Zero Trust** > **Integrations** > **Identity providers**.
1. Under **Your identity providers**, select **Add new identity provider**.
1. Select **One-time PIN** and save it.

You may instead add Google, GitHub, Microsoft Entra ID, or another SSO provider in the same location.

## Enable Independent MFA

MFA options remain unavailable in an Access application until at least one organization-level method is enabled.

1. Go to **Zero Trust** > **Access controls** > **Access settings**.
1. Under **Allow multi-factor authentication (MFA)**, enable **Authenticator application**, **Security key**, **Biometrics**, or a combination.
1. Set an authentication duration, such as `1 hour` or **Require every login**.
1. Leave **Apply global MFA settings by default** disabled when MFA should apply only to `/admin`.
1. Save.

PIV key and FIDO2 key are for SSH infrastructure applications, not browser access to Vaultwarden.

## Create the Admin Application

1. Go to **Zero Trust** > **Access controls** > **Applications**.
1. Select **Create new application** > **Self-hosted and private** > **Add public hostname**.
1. Enter `Vaultwarden Admin` as the application name, select `<VAULTWARDEN_DOMAIN>`, and set the path to `/admin`.
1. Set session duration to `1 hour`.
1. Create an **Allow** policy named `Allow Vaultwarden administrators`.
1. Add an **Include** rule using selector **Emails** with each administrator's exact email address. Do not use **Everyone** or a broad email-domain rule unless every matching user should administer Vaultwarden.
1. In the application **Authentication** section, open the **MFA** tab.
1. Select **Custom MFA settings**, choose enabled MFA methods, set the duration, and save.

Cloudflare Access is deny-by-default: users who do not match an Allow policy cannot reach `/admin`.

## Enroll MFA Devices

1. Open `https://<your-team-name>.cloudflareaccess.com`.
1. Sign in using an identity allowed by the admin policy.
1. Select **Account** > **MFA devices** > **Add an MFA device**.
1. Enroll the configured authenticator. Enroll a second recovery method where possible.

The direct enrollment address is `https://<your-team-name>.cloudflareaccess.com/AddMfaDevice`.

## Verify Protection

1. In a private browser window, open `https://<VAULTWARDEN_DOMAIN>/admin`.
1. Confirm that only an allowed identity can pass Cloudflare Access and MFA.
1. Confirm Vaultwarden subsequently asks for `ADMIN_TOKEN`.
1. Test normal browser, desktop, and mobile Vaultwarden access. Keep the main hostname outside interactive Access if any client cannot authenticate normally.
