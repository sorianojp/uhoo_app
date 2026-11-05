# Uhoo! — Unlisted App Distribution (Guideline 3.2 fix)

Apple rejected submission `9f2ce2e6-f6b2-4ec0-a07e-d4d8a63bfe66` (version 1.0,
build 2) under Guideline 3.2 because the app is for one organization but was set
to public distribution. The previous reply asking for public distribution anyway
did not work, so this one switches to unlisted distribution. No code changes
are needed.

## Order of steps

1. Send the **App Review reply** below in App Store Connect
   (App Review > the rejected submission > Reply to App Review).
2. Submit the **Unlisted App Distribution request** at
   https://developer.apple.com/support/unlisted-app-distribution/ while signed
   in as the Account Holder or an Admin.
3. Wait for Apple's email approving the request. After approval, App Store
   Connect > Pricing and Availability > App Distribution Method shows
   **Unlisted App**.
4. Resubmit the same version for review. If App Review says the version must be
   approved first, resubmit it as is: the unlisted setting then applies to the
   approved version.
5. After release, share the App Store link
   (`https://apps.apple.com/app/id6814329162`) with students and staff through
   STEP, the university website and official university pages. Searching the
   App Store won't find the app.

---

## 1. Unlisted App Distribution request (form answers)

**App name:** Uhoo!

**Apple ID:** 6814329162

**Bundle ID:** com.arzatech.uhoo

**Is this a new app or an app already on the App Store?**
New app. Version 1.0 is currently in App Review
(submission ID 9f2ce2e6-f6b2-4ec0-a07e-d4d8a63bfe66).

**Describe the app and its intended audience:**

Uhoo! is the official campus messaging app of Universidad de Dagupan
(Dagupan City, Philippines). It lets the university's students, faculty and
staff send direct and group messages, share files and voice messages, and
receive notifications about campus conversations. Users sign in only with
their university-issued STEP account through the university's single sign-on.
There is no public registration and no paid content.

The intended audience is the enrolled students, faculty and staff of
Universidad de Dagupan. The app is not meant for the general public.

**How will users get the app link?**

The university will share the App Store link with its own members through
the STEP student and employee portal, official university announcements and
email, the university website, and its official social media pages.

**Why is unlisted distribution the right fit?**

Most users are students on their own iPhones and iPads, which the university
does not manage, so custom app distribution through Apple School Manager and
MDM is not practical. Unlisted distribution lets these users install the app
normally from the App Store with a direct link, while keeping the app out of
public search results as App Review requested under Guideline 3.2.

---

## 2. Reply to App Review (Resolution Center)

Hello App Review Team,

Thank you for your feedback on Guideline 3.2.

You are correct that Uhoo! is intended for a single organization. It is the
campus messaging app of Universidad de Dagupan, and only the university's
students, faculty and staff can sign in, using their university-issued STEP
accounts.

Following your recommendation, we have submitted a request for Unlisted App
Distribution. Our users are mainly students using their own iPhones and iPads,
which are not enrolled in Apple School Manager or device management, so
unlisted distribution is the best fit. The university will share the direct App
Store link only through its own official channels.

For completeness, our answers to your questions:

1. Yes. The app is restricted to verified students, faculty and staff of
   Universidad de Dagupan.
2. It is designed for one organization only, Universidad de Dagupan. Other
   companies or organizations cannot become clients.
3. No features are intended for the general public.
4. The university issues accounts through its existing STEP system. There is
   no public or self-service registration.
5. There is no paid content, subscription or in-app purchase. The university
   provides the service free to its members.

We will resubmit once the unlisted distribution request is approved. Please let
us know if you need anything else.

Thank you,
John Paul Soriano
