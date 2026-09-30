# TRICRYPT: FINAL FRONTEND PROMPT (FLUTTER + DART, ANDROID + iOS)

**App:** TriCrypt, a biometric-authenticated data concealment app (image steganography + AES-256).
**Scope:** Build the complete UI, navigation, local database and auth flow. Encryption, steganography and transfer are implemented behind the stub functions in section 12. Fake the stubs with timers so the whole app runs end to end.

\---

## 0\. PROJECT SETUP

**Packages:** `supabase\\\_flutter`, `flutter\\\_secure\\\_storage`, `local\\\_auth`, `image\\\_picker`, `sqflite`, `path`, `path\\\_provider`, `image\\\_gallery\\\_saver`, `qr\\\_flutter`, `mobile\\\_scanner`, `permission\\\_handler`, `connectivity\\\_plus`.

**Folder structure:**

```
lib/
  main.dart
  core/        (theme, constants, validators, widgets, services)
  features/
    auth/      (splash, login, signup)
    home/
    hide/
    view/
    gallery/
    barcode/   (barcode, scanner)
    preview/
  data/        (album\\\_db.dart, secure\\\_store.dart, stubs.dart)
```

**Platforms:** Android (min SDK 23) and iOS (min 13).

* **iOS Info.plist:** `NSFaceIDUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`.
* **Android manifest:** `CAMERA`, `USE\\\_BIOMETRIC`, `INTERNET`, `ACCESS\\\_NETWORK\\\_STATE`, `ACCESS\\\_WIFI\\\_STATE`, `CHANGE\\\_WIFI\\\_STATE`, media/storage permissions. Use `FlutterFragmentActivity` for local\_auth.
* Lock orientation to portrait.

\---

## 1\. THEME (GLOBAL)

* Background #0A0A0A, cards #121212, accent cyan #4DFFEA, error red #FF4D4D, text white/grey.
* Titles: bold monospace-style display font with a peach/coral gradient (ShaderMask).
* Upload boxes and inputs: bracket-corner borders (CustomPainter), cyan neon glow.
* Buttons: bordered cyan, full width, uppercase text, disabled state greyed out.
* **Bundle fonts** in `assets/fonts` and declare them in `pubspec.yaml`. Do not use google\_fonts (needs internet).
* Dark status bar and navigation bar on Android and iOS.
* Haptic feedback on toggles and buttons.

\---

## 2\. APP FLOW

Splash → (session found → Home) or (no session → Login) → Sign Up ↔ Login → Home.
Home, Hide, View, Gallery and Barcode share a **persistent bottom bar**. Scanner and Preview are pushed screens with a back arrow.

\---

## 3\. SPLASH

Centered logo with a cyan glow fade-in (1.5 s). Read the saved session from flutter\_secure\_storage. **No network call.**

* Session exists → Home.
* Otherwise → Login.
* If "Remember me" was unchecked last time, clear the session on launch and go to Login.

\---

## 4\. LOGIN (SIGN IN) — online only

* **Email:** standard email format validation (contains "@", a domain, a TLD) — no domain restriction. Red inline error below the field.
* **Password:** minimum 8 characters, 1 uppercase, 1 digit, 1 special from `\\\*^$%#@.`. Red inline error below the field. Eye icon toggles show/hide.
* **Remember me** checkbox bottom-left, checked by default.
* **SIGN IN** button: bordered, full width. Shows a spinner and is disabled while loading.
* **Link:** "Don't have an account? **Sign Up**".
* **Success:** store the session in flutter\_secure\_storage, save the Supabase User ID and username locally, go to Home.
* **Failure:** red error banner at the top, no navigation.
* **Offline:** banner "Internet required to sign in."
* **Supabase is used here and on Sign Up only — every other screen is fully offline.**

## 5\. SIGN UP — online only

Same layout as Login. Fields: Name, Email, Password, Confirm Password (same rules, passwords must match). Button **SIGN UP**. Same banners, plus a "Check your email to verify" message if verification is enabled in Supabase.

\---

## 6\. HOME

* **Header:** logo top-left (tap = Home). Profile avatar circle top-right with the user's initial. Tapping it opens a menu with **Logout**, which clears secure storage (session, User ID, username), keeps the Album DB, and goes to Login.
* **Greeting:** "Welcome, {username}" on first login, "Welcome back, {username}" after, by device time. Subtext: "Your files stay on your device, always."
* **4 cards in a 2×2 grid** (dark card, cyan border, icon, bold title, description):

  * **Hide:** eye-slash. "Encrypt one or more files into a cover image." → Hide.
  * **View:** eye. "Reveal a hidden file with your fingerprint or passkey." → View.
  * **Gallery:** stacked layers with a badge count from the DB. "Encrypted files live on your device, not on our servers." → Gallery.
  * **Barcode:** QR. "Send an encrypted file to another device with a scan." → Barcode.
* No network calls on this screen.

**Bottom bar (persistent):** lock (Hide), unlock (View), layers with badge (Gallery), QR (Barcode). The active tab is cyan.

\---

## 7\. HIDE (ENCODE)

* **Title:** "Hide". No back arrow.
* **COVER IMAGE:** one square upload box (1:1), "+" icon centered, label above. Tap to pick from gallery or camera. Thumbnail after selection.
* **Capacity line** directly below the cover box, shown as soon as a cover is picked: "Capacity: 8.2 MB", computed via `getCoverCapacity` (on-device, from pixel dimensions).
* Capacity shown is the backend's computed value at the moment the cover is selected. If the batch's actual encode later needs a different embed quality (backend-decided), the capacity check re-runs silently before processing starts — if the batch no longer fits, show the same over-capacity error at that point instead of failing mid-queue.
* **SECRET FILES:** a separate multi-select picker below, label "SECRET FILES (1 or more)". Picking opens the gallery/file picker in multi-select mode. Selected files render as a horizontal thumbnail strip with a remove "×" on each, a running count ("3 files selected"), and a running total size.
* **Capacity check, live:** as files are added, compare running total against capacity.

  * Under capacity: capacity line stays neutral cyan, shows "Capacity: 8.2 MB · Using 3.1 MB".
  * Over capacity: capacity line turns red, an inline error appears under the secret-files strip: "Selected files (9.4 MB) are larger than this cover image can hold (8.2 MB). A cover image can only hide data up to roughly its own size — pick a larger cover image or remove some files." HIDE button stays hidden until resolved.
* **2 independent toggles** (both can be on at once, neither forces the other off), default off: **BIOMETRIC** and **PASSKEY**. If no fingerprint or Face ID is enrolled, disable BIOMETRIC with the note "No fingerprint or Face ID enrolled". If both are on, both credentials are required together before the queue starts.
* **State machine:** Idle → ToggleSelected → Processing → Done.

  1. **HIDE** button fades/slides in only when a cover image is set, at least one secret file is selected and within capacity, and at least one toggle is on.
  2. Tap **HIDE**:

     * PASSKEY on: dialog with Passkey + Confirm Passkey (eye icons, same validation style as Login's password field).
     * BIOMETRIC on: local\_auth prompt.
     * Both on: passkey dialog first, then biometric prompt — both must succeed before processing starts.
  3. Processing shows a **queue list**, one row per secret file (thumbnail, filename, determinate progress bar 0–100%), fed by the same shared cover image and the same credential(s) across the whole batch. Toggles, the file picker and back navigation are locked, with a "Cancel?" dialog if the user tries to leave mid-batch.
  4. As each row hits 100% it gets its own **DOWNLOAD** and **VIEW** actions inline. A "Download all" button appears once every row is done.
* **DOWNLOAD** saves that file's output PNG to the gallery with a snackbar "Saved to gallery". **VIEW** opens Preview for that output.
* Save one Album DB record per output file, `type = "encoded"`.
* Errors (red banner, per row where applicable): secret too large for the cover image, image not selected, operation failed.
* Leaving the screen resets to Idle and clears the queue.

\---

## 8\. VIEW (DECODE)

* **Title:** "View". Single upload box labeled **ENCODED IMAGE**, "+" centered. Same 2 independent toggles as Hide: **BIOMETRIC** and **PASSKEY**, both selectable together.
* **Auth requirement matches how the file was encoded**, read from its Album DB record:

  * Encoded with biometric only → REVEAL asks for biometric only.
  * Encoded with passkey only → REVEAL asks for passkey only.
  * Encoded with both → REVEAL requires both, in sequence, before decoding starts.
* **REVEAL** button appears only when an image is selected and the required toggle(s) for that file are satisfied.
* Tap **REVEAL**: PASSKEY shows a dialog (eye icon, no Confirm field), BIOMETRIC shows the local\_auth prompt, both-required runs passkey then biometric.

  * **Success:** progress bar 0–100% (controls locked), then **VIEW** and **Download**.
  * **Failure:** red "Access Denied" state, no progress bar, back to Idle after 2 s.
  * **Not a TriCrypt image:** banner "This image has no hidden data."
* Save a record to the Album DB with type "decoded".

\---

## 9\. GALLERY (ALBUM)

* **Title:** "Gallery". No back arrow.
* This screen is TriCrypt's own tracked index (Album DB), separate from the phone's native Photos app — it is how the user finds which images are still encrypted and which have already been revealed, even though the underlying files sit in the normal device gallery.
* **Filter tabs** at the top: **All / Encrypted / Decoded**. "Encrypted" shows `type = "encoded"` or `"received"` rows not yet decoded; "Decoded" shows `type = "decoded"` rows.
* **Empty state:** centered "No items yet." with subtext "Hide or reveal an image to see it here."
* **With items:** 2-column grid, newest first, placeholder while thumbnails load. Each thumbnail has a small badge in the corner: a lock icon for still-encrypted items, an open-lock icon for decoded items.
* **Tap** an item to open Preview. **Long-press** shows a delete confirmation dialog, and confirming removes the file and the DB row.
* The badge count on Home and the bottom bar updates live, and reflects the "Encrypted" (not yet decoded) count.

\---

## 10\. BARCODE

* **Title:** "Barcode". Subtitle "SELECT IMAGE TO SHARE".
* **Upload box:** rectangular (about 4:3), bracket-corner border, "+" icon. Tap to pick from Gallery or the device. Preselected if opened from Preview via "Share via QR".
* **GENERATE CODE** (bordered, full width): if no image is selected, show the inline error "Select an image first". Otherwise call `sendFile`, replace the upload box with the QR (qr\_flutter) and "Waiting for scan...". Add a Cancel button while waiting.
* **On connection:** before any bytes transfer, show a **4-digit confirmation code** on this screen, large and centered, with the text "Ask the other device to confirm this code matches." Transfer only proceeds after the sending user taps **Confirm** here and the receiving user confirms the matching code on their Scanner screen. Either side can tap **Reject** to abort.
* After confirmation: progress indicator, then a "Sent" checkmark.
* **SCAN TO RECEIVE** (second bordered button): opens the Scanner.

## 11\. SCANNER, PREVIEW

**Scanner:** back arrow top-left, mobile\_scanner camera view with a cyan bracket-corner frame. After a scan, show the same **4-digit confirmation code** the sender sees, with "Confirm" and "Reject" buttons. Only after the user taps Confirm does "Receiving..." with a progress bar start, then a "Received" checkmark and an "Open Gallery" button. The file is added to the Album DB with `type = "received"`, still encrypted. Show an error banner on failure, timeout, or code mismatch.

**Preview:** back arrow top-left, full-screen zoomable image (InteractiveViewer), and **DOWNLOAD** and **Share via QR** buttons at the bottom.

\---

## 12\. DATA AND LOGIC SEPARATION

**Album table (sqflite):** `id INTEGER PK, filename TEXT, filepath TEXT, type TEXT (encoded/decoded/received), encryption\\\_type TEXT (passkey/biometric/both), timestamp INTEGER, thumbnail\\\_path TEXT`.
`filepath` always points at the file's location in the device's own gallery — this table is an index, not a copy store.

**Secure storage keys:** `session`, `user\\\_id`, `username`, `remember\\\_me`, and `cred\\\_<fileId>` for per-file credentials.

**Stubs (backend replaces these; fake with a timer until then):**

```dart
Future<int> getCoverCapacity(File cover); // bytes, for the live capacity line — computed locally from image pixel dimensions, no network call
Future<void> encodeImage(
  File cover,
  List<File> secrets,
  String credential,
  void Function(int fileIndex, double progress) onProgress,
);
Future<File> decodeImage(File encoded, String credential, void Function(double) onProgress);
Future<void> sendFile(File file, String confirmationCode);
Future<File> receiveFile(String confirmationCode);
```

The UI only displays progress and results from these. `onProgress` for `encodeImage` reports per-file, driving each queue row independently. `credential` is expected pre-combined (HKDF) by the caller when both biometric and passkey are on — the stub does not do the combining.

\---

## 13\. GLOBAL RULES

* **Online usage:** Supabase is used **only** for Login, Sign Up and the silent session refresh. Hide, View, Gallery and Barcode are fully offline with zero internet calls once past login.
* **Session handling:** If a saved session exists, always open Home, even when offline and even if the token has expired. Never force logout because of a failed refresh while offline. Attempt a silent refresh only when the internet is available, and log out only on an explicit Logout tap or if Supabase reports the session as invalid while online.
* **Connectivity:** Use connectivity\_plus to choose the correct banner on Login and Sign Up. Never show connectivity errors on offline screens.
* **Capacity check:** getCoverCapacity runs entirely on-device (reads image dimensions, computes usable bytes). Never call this over network, even as a stub.
* **Titles:** Hide, View, Gallery and Barcode, used on both Home and the screens.
* **Layout:** Wrap every screen in SafeArea + SingleChildScrollView so notches, small phones and the iOS home indicator never clip content.
* **Permission denied** (camera, gallery, biometric): show a pop up that contains the permission for the backend work to access the camera , gallery , biometric Show this three options " Always Allow " ,"While using the app", "Only Once".
* **States:** Every async action has a loading state, an error banner and a disabled-button rule. Buttons stay hidden or disabled until their inputs are valid.
* **Animations:** Fade/slide for HIDE/REVEAL button appearance, smooth progress animation, fade transitions between screens.
* **Back handling:** Back navigation during Processing shows a "Cancel?" dialog. Leaving Hide or View resets the state to Idle.
* **Security UI:** Never show passkeys in plain text by default, never log credentials, and mask the screen in the app switcher (`FLAG\\\_SECURE` on Android, blur overlay on iOS) on Hide, View and Preview.

