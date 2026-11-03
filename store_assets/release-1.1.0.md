# Release 1.1.0 (build 5)

The first update since launch. Brings the app level with the web app at
https://uhoo.udd.edu.ph.

## What's new — Google Play (≤ 500 characters)

```
• Voice messages: record and play them right in the chat
• Class chats: teachers start a group for any STEP class; students join automatically
• Seen by: check who has read your message
• Saved messages: keep important messages and jump back to them
• @mentions, link previews and inline photos
• Drafts are kept per chat, and Delivered/Seen updates
• A fresh look that matches the Uhoo! website
```

## What's new — App Store (≤ 4,000 characters)

```
Uhoo! 1.1 brings the app level with the Uhoo! website.

• Voice messages — record and play them right in the chat.
• Class chats — teachers start a group chat for any of their STEP classes, and
  students join automatically, even if they sign in to Uhoo! later.
• Seen by — open Message info to see who has read your message.
• Saved messages — save important messages and jump back to them anytime.
• @mentions with suggestions, link previews and photos shown in the chat.
• Unsent text is kept as a draft in each chat.
• Pinned messages take you straight to the message.
• A refreshed design that matches the Uhoo! website, in light and dark.
```

## New permission: microphone

Used only to record voice messages, and only after the person taps the mic
button. Nothing is recorded in the background.

- **iOS:** `NSMicrophoneUsageDescription` is already in Info.plist —
  "Record voice messages to send in your conversations."
- **Android:** `RECORD_AUDIO` is requested at runtime the first time someone
  records.

### Google Play — Data safety form

Under **Data collected → Audio → Voice or sound recordings**:

- Collected: **Yes** (voice messages a user chooses to send)
- Shared with third parties: **No**
- Processed ephemerally: **No** (stored as message attachments)
- Required or optional: **Optional** (users choose whether to record)
- Purpose: **App functionality**
- Encrypted in transit: **Yes**; users can request deletion: as for other
  messages (unsend)

### App Store — App Privacy

Add **Audio Data** → linked to the user, used for **App Functionality**, not
used for tracking.

### App Review notes (add to the existing notes)

```
Version 1.1 adds voice messages. The app asks for microphone access only when
the user taps the microphone button in a chat to record a voice message.
Recordings are sent as message attachments to the other participants and are
not used for any other purpose.
```

## Before submitting

1. Try the release build on a real phone for ~10 minutes: record and play a
   voice note (and one recorded on the web), start a class chat as a teacher,
   save a message and open it from Profile → Saved messages, check light and
   dark mode.
2. New screenshots: the store screenshots show the 1.0 design. Replace
   `screenshot-*.png` (and `ios/`) with ones from 1.1.

## Builds

```sh
flutter build appbundle --release   # Play Console → Production → Create release
flutter build ipa --release         # Upload with Transporter or Xcode Organizer
```
