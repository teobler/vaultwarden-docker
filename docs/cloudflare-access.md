# Cloudflare Access and MFA

Protect only `https://<VAULTWARDEN_DOMAIN>/admin` with interactive Cloudflare Access. Do not put the complete Vaultwarden hostname behind an interactive Access login until every Bitwarden client you use has been tested: desktop and mobile applications may not support Access's browser redirect login for API calls.

Cloudflare Access and Vaultwarden's `ADMIN_TOKEN` are independent protections. Configure `ADMIN_TOKEN` as an Argon2id PHC hash, generated with `docker run --rm -it vaultwarden/server:latest /vaultwarden hash`; retain the plaintext password only in your password manager.

## Configure the Login Method

Configure the identity provider that administrators will use for both the `/admin` application and the Access App Launcher. In this deployment, select **Cloudflare SSO** wherever Cloudflare prompts for a login method. The App Launcher policy email must exactly match the email identity emitted by that provider.

Cloudflare One-time PIN, Google, GitHub, Microsoft Entra ID, and other identity providers are alternatives. If you use one, select that same provider in both locations below and use the email it returns in both Allow policies.

## Enable the App Launcher for MFA Enrollment

The Cloudflare Access MFA setup button redirects to the organization App Launcher. The launcher is disabled by default, and it has its own policy which is separate from the Vaultwarden Admin application. Create its narrowly scoped Allow policy before testing `/admin`; otherwise MFA setup ends at `#/NoAuth` with the App Launcher disabled message.

1. Go to **Zero Trust** > **Access controls** > **Access settings**.
1. Under **Manage your App Launcher**, select **Manage**.
1. On **Policies**, create an **Allow** policy named `Allow Vaultwarden MFA enrollment`.
1. Add an **Include** rule using selector **Emails** with the exact email address of the Cloudflare SSO identity used to access `/admin`.
1. On **Authentication**, enable **Cloudflare SSO** and save.

Do not use **Everyone** or a broad email-domain rule. Enabling the launcher for this identity only permits its account-management and MFA enrollment page; it does not grant access to Vaultwarden.

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
1. Add an **Include** rule using selector **Emails** with the same exact Cloudflare SSO email allowed by the App Launcher policy. Do not use **Everyone** or a broad email-domain rule unless every matching user should administer Vaultwarden.
1. In the application's **Authentication** section, enable **Cloudflare SSO**.
1. In the application **Authentication** section, open the **MFA** tab.
1. Select **Custom MFA settings**, choose enabled MFA methods, set the duration, and save.

Cloudflare Access is deny-by-default: users who do not match an Allow policy cannot reach `/admin`.

## Enroll MFA Devices

1. In a private browser window, open `https://<VAULTWARDEN_DOMAIN>/admin`.
1. At the Access login screen, select **Cloudflare SSO** and sign in with the email permitted by both Allow policies.
1. When Access requires MFA, select **Set up**. Access redirects to the enabled App Launcher for enrollment.
1. Select **Account** > **MFA devices** > **Add an MFA device**, then enroll the configured authenticator.
1. Enroll a second recovery method where possible, then return to `https://<VAULTWARDEN_DOMAIN>/admin`.

The direct enrollment URL, `https://<your-team-name>.cloudflareaccess.com/AddMfaDevice`, is optional and also requires a matching App Launcher policy and enabled **Cloudflare SSO** authentication method.

## Verify Protection

1. In a private browser window, open `https://<VAULTWARDEN_DOMAIN>/admin`.
1. Confirm Access offers **Cloudflare SSO**, only the exact allowed identity can pass it, and MFA is required.
1. Confirm Vaultwarden subsequently asks for `ADMIN_TOKEN`.
1. Confirm an identity excluded from either the App Launcher policy or the Vaultwarden Admin policy cannot complete the MFA setup and access the admin page.
1. Test normal browser, desktop, and mobile Vaultwarden access. Keep the main hostname outside interactive Access if any client cannot authenticate normally.
