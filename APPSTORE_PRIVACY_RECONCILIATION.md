# xBill App Store Privacy Reconciliation

Last reconciled: 2026-06-14

This file aligns the App Store Connect privacy questionnaire, `PrivacyInfo.xcprivacy`, and the public privacy policy at `https://xbill.vijaygoyal.org/privacy`.

## App Store Connect Privacy Labels

Use these answers for the app privacy questionnaire.

### Tracking

- Tracking: No
- Data used to track users across apps and websites: None

### Contact Info

- Email Address
  - Collected: Yes
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality
- Name
  - Collected: Yes
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality
- Other User Contact Info
  - Includes optional Venmo and PayPal.me handles.
  - Collected: Yes, only if the user enters payment handles
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality

### User Content

- Photos or Videos
  - Includes optional profile avatar uploads.
  - Receipt images are OCR-only temporary inputs and are not uploaded or attached to expenses.
  - Collected: Yes, only if the user chooses a profile photo
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality

### Financial Info

- Other Financial Info
  - Includes groups, expenses, splits, settlements, IOUs, currencies, notes, and comments related to shared expenses.
  - Collected: Yes
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality

### Contacts

- Contacts
  - Includes selected contact email addresses chosen through Apple's contact picker for friend/member discovery. xBill does not upload the full address book.
  - Collected: Yes, only when the user selects contacts
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality

### Identifiers

- User ID
  - Includes Supabase/auth profile identifiers used to associate groups, memberships, expenses, comments, and device tokens with the signed-in account.
  - Collected: Yes
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality
- Device ID
  - Includes APNs device tokens if the user allows notifications.
  - Collected: Yes, only after notification registration
  - Linked to user: Yes
  - Used for tracking: No
  - Purpose: App Functionality

## Local Manifest Alignment

`xBill/PrivacyInfo.xcprivacy` declares:

- Email Address: linked, app functionality
- Name: linked, app functionality
- Other Financial Info: linked, app functionality
- Photos or Videos: linked, app functionality
- Contacts: linked, app functionality
- User ID: linked, app functionality
- Other User Contact Info: linked, app functionality
- Device ID: linked, app functionality
- Tracking: false
- Required reason API: UserDefaults `CA92.1` for app-only defaults and `1C8F.1` for App Group defaults shared with the widget

`xBillWidget/PrivacyInfo.xcprivacy` declares:

- No collected data
- Tracking: false
- Required reason API: UserDefaults `CA92.1` and `1C8F.1`

The widget reads local App Group balance/cache data for display. Sensitive cached app data is encrypted; the widget-facing balance summary is local app functionality, not server collection by the widget target.

## Privacy Policy Alignment

`web/privacy/index.html` covers:

- Supabase authentication, database, storage, realtime updates, and backend functions
- Resend invite emails
- APNs/device tokens
- Contact-email lookup
- Optional avatar/profile-photo upload
- OCR-only receipt scanning with no receipt image upload
- Exchange-rate requests to `open.er-api.com` without user identifiers
- Local app preferences and widget/offline cache
- Account deletion and retained shared expense history

## Pre-Submission Checks

- App Store Connect privacy labels must match the "App Store Connect Privacy Labels" section above.
- App Store Connect privacy policy URL must be `https://xbill.vijaygoyal.org/privacy`.
- Deploy the full `web/` folder to Cloudflare Pages after privacy copy changes.
- Verify:
  - `curl -L -I https://xbill.vijaygoyal.org/privacy`
  - `curl -L https://xbill.vijaygoyal.org/privacy | head`
- Confirm receipt images remain OCR-only before submission. If receipt attachment/upload is reintroduced, update this file, the privacy manifest, and the public privacy policy.
