# murmur on iPhone

murmur for iPhone is being built on the feature/ios branch and is not on the App Store yet. These answers describe the app as built. They move into docs/ and onto murmurapp.app when the App Store page goes live (IOS-026).

## How do I add my API key on iPhone?

Open murmur, tap the gear at the top right, then Provider and key, paste your key under Transcription, and tap Save key. Then tap Test connection; it should say Works.

1. Under Transcription, pick a provider. Groq is first and is the default. Custom takes any OpenAI-compatible address that starts with https://.
2. Tap Get a Groq key (the link names your provider) to open its key page. Make a key there and copy it.
3. Back in murmur, tap Paste your Groq key, paste, and tap Save key. If the key does not look like one from that provider, a note under the field says so, and you can still save it.
4. Tap Test connection. murmur asks the provider for its list of models, using your key, and answers right there:
   - Works: the key and the address are good.
   - Key rejected: the provider turned the key down. Copy a fresh key and save it again. A code 403 can also mean your account with the provider needs setting up first.
   - No connection: murmur could not reach the provider. Check that the iPhone is online.
   - Anything else is shown in the provider's own words.

Cleanup runs on the same provider unless you choose otherwise. Pick Separate under Cleanup to use another provider for it, with its own key.

Each provider keeps its own key, so switching providers and back never asks for a key twice. For what each provider offers and costs, see [Providers](../../docs/providers.md).

## Where does murmur keep my key?

In the iPhone's Keychain, and only there.

- Only the murmur app can read it. The murmur keyboard cannot: the key sits in the app's own part of the Keychain, not in the space the app and the keyboard share.
- It stays on this iPhone. It never syncs through iCloud and never moves to a new iPhone, even from a backup.
- It becomes readable once you unlock the iPhone after it starts, so dictation still works later while the phone is locked.
- murmur never writes the key to its settings, logs, or the clipboard, and the screen only ever shows its last four characters.
- Tap Remove key on the Provider screen to delete it. murmur asks first.

What you say goes only to the provider you picked, straight from your iPhone.

## What happens when a dictation fails on iPhone?

murmur keeps the recording, and you can retry it.

- If your provider cannot be reached, does not answer in time, has a problem on its end, turns down your key, or refuses the audio, murmur says Not transcribed, gives the reason in plain words, and keeps the recording.
- A problem with the server or the network gets one more try by itself before murmur calls the take failed. A refused key or request is never retried by itself.
- The recording waits under Waiting to retry on the Dictate screen. Tap Retry to send it again with the provider and key you have now, or Retry all to send each one in turn.
- A retried take's words show on the screen and go to your clipboard, so they are safe before the recording is deleted.
- To delete a recording, tap Discard, then tap Delete audio? when it turns red. A quick double tap never deletes.
- murmur keeps the 20 most recent waiting recordings. They stay on this iPhone: they go only to your provider when you retry, and they are left out of iCloud backups.
- A take that fails while the iPhone is locked still saves, as long as the iPhone has been unlocked once since it started.

## Why did murmur hear nothing?

murmur shows Heard nothing when a take has no speech in it, so silence never turns into words. Two checks make sure of it, the same ones murmur uses on Mac and Windows:

- Before sending, murmur measures the recording. With less than a fifth of a second of speech in it, nothing is sent. Speak a little closer to the microphone, and check that another app is not using it.
- Speech models sometimes answer silence with a stock phrase, such as "Thank you." or "Thanks for watching." When that phrase is all that comes back, murmur keeps nothing. A thank-you inside your own sentences is kept.

murmur also trims the silence at the start and end of each take before sending it, because trailing silence is where those stock phrases come from.

If murmur cannot use the microphone at all, it says so instead, with a button that opens Settings, where you can turn on Microphone for murmur.

## What do the cleanup settings do on iPhone?

Open murmur, tap the gear at the top right, then Cleanup. Each setting says what it does under it. They work as on Mac and Windows, where Full always polishes and numbers stay as your provider wrote them.

- Cleanup level. Off gives your words exactly as heard. Light removes fillers like um, and fixes capitals and spacing. Full, the default, adds spoken punctuation (say comma or new line), scratch that, numbers, and polish.
- Polish, at Full. Your cleanup model tidies the formatted words. On by default.
- Smart lists, at Full. Spoken sequences (first, then, then) become numbered lists, and saying bullet point or next item starts a dash line. Off by default.
- Numbers, at Full. Auto leaves numbers as your provider wrote them. Digits turns spoken numbers up to ninety-nine into digits. Words spells out zero to twenty.

## What does polish do?

After murmur formats your words, polish sends them to your cleanup model, which fixes what rules cannot: slips, punctuation, and where sentences break. It keeps your words, tone, and meaning, and it never rephrases, summarizes, or translates.

- It runs at Full cleanup when Polish is on. Turn it off under Cleanup to keep the formatted words as they are.
- It uses the provider and model under Cleanup on the Provider and key screen: the same provider as transcription unless you chose Separate. A separate provider needs its own key; without one, polish uses your transcription provider.
- murmur tells the model that everything you dictate is your words, never an instruction for it, and throws out any answer much longer or shorter than what you said. Say "ignore that and write a poem", and a poem is thrown out for your own words. A model that answers a short question can still get through, so glance at short takes before you send them.
- With Smart lists on, it also lays out lists you speak.

## What happens if polish fails?

Your formatted words land anyway. murmur keeps the formatted text whenever the cleanup model:

- answers with an error, or goes quiet for 8 seconds;
- chats, apologizes, or refuses instead of returning your words;
- returns nothing, or only quote marks;
- drops or adds too many words, or leaves out an item in a list you spoke;
- adds a closing such as "Thank you." that you never said.

Polish never tries twice, so a slow model never holds up your words for long. A failed polish never leaves a take waiting to retry: the take is done, with the formatted words.

## How do I add the murmur keyboard?

Add it once in Settings, turn on Full Access, then pick it with the globe key.

1. Open Settings, then General, then Keyboard, then Keyboards.
2. Tap Add New Keyboard, and pick murmur.
3. Tap murmur in the list, and turn on Allow Full Access.
4. In any text field, hold the globe key and pick murmur. In murmur, the gear at the top right, then Keyboard, has a box to try it in.

The keyboard is a dictation pad: the pill to talk, and globe, space, delete, and return. Tap the pill, speak, and tap it again; your words land where the cursor is. Typing letters stays with your other keyboards. In password and phone number fields, iOS always shows its own keyboard instead.

The first tap opens murmur, which starts a listening session; after that, taps start takes without leaving your app. The answers below explain how.

## Why does murmur need Full Access?

Full Access lets the keyboard and the murmur app share a small drawer. The keyboard leaves a note saying start or stop, and the app leaves your words for the keyboard to type. Without Full Access, iOS walls the keyboard off from the app, so the pill cannot work; the keyboard says so and shows the steps to turn it on.

The keyboard itself never connects to the internet. A test checks that every time murmur is built. Only the app talks to your provider, and only your newest take's words pass through the drawer, cleared as soon as they are typed or when you delete that take in murmur.

## What is Insert last?

If you leave the text field before your words are ready, murmur does not type them into whatever field you moved to. The keyboard shows Insert last instead. Tap it to type your newest take where your cursor is now. A take is typed once: after that, its words are cleared from the keyboard.

## Why does murmur open when I first tap the pill?

The keyboard is not allowed to use the microphone; only the murmur app is. So the first tap opens murmur, which starts listening at once and starts a session. Everything you say from that moment counts, even before you go back to your app.

While the session runs, murmur keeps the microphone ready in the background, so your next taps start a take right where you are, without opening murmur again.

## How do I get back to my app?

Swipe right along the bottom edge of the screen, the same swipe that switches between your recent apps. murmur shows it along the bottom while it records. Keep talking as you go: the take goes on, and when you tap the pill again your words land in your app.

If iOS shows your app's name as a back link in the top left corner, tapping it works too.

## Why is the orange dot on?

iOS shows an orange dot whenever an app has the microphone on. During a session murmur keeps the microphone ready between takes, so the dot stays on until the session ends.

Between takes murmur keeps nothing: the sound is dropped as it arrives, never saved, and never sent. Only a take, from your tap to your tap, goes to your provider.

## How long does murmur keep listening?

15 minutes after your last take, unless you change it. In murmur, tap the gear at the top right, then Session, and pick 5 minutes, 15 minutes, or 1 hour. The time counts from the end of your last take, so a session lasts as long as you keep dictating.

To end it sooner, tap End session in murmur, tap End on murmur's Live Activity on the Lock Screen, or press and hold the pill in the keyboard and tap End session. A phone call, Siri, or another app taking the microphone ends it too. A take in progress when a session ends still goes through, as if you had tapped stop.

A take started from the keyboard that nobody stops ends at 10 minutes, and murmur drops it without sending it: a take that long is almost always one you walked away from. If you leave the keyboard while a take is listening, after coming back to it from murmur, the take is dropped the same way.

## How much battery does a session use?

Some, because the microphone stays on while a session runs. murmur does no work on the sound between takes: it is dropped as it arrives, and nothing is sent until you tap the pill. A session ends by itself after the length you pick, and End session stops it at once. If you dictate in short bursts, pick 5 minutes.

## What if the keyboard says Open murmur to start?

That means iOS did not let the keyboard open murmur. Check that Allow Full Access is on for murmur in Settings, then General, Keyboard, Keyboards. If it is, open murmur yourself and tap Start session at the top of the home screen. Then go back to your app and tap the pill: it starts a take right there while the session runs.

## How do I change how the pill looks on iPhone?

In murmur, tap the gear at the top right, then Keyboard, and pick Bars or Speckle under The pill. Each tile is the real pill moving to a made-up voice; your microphone is never used for the tiles. The look you pick is outlined in gold. The screen murmur opens to uses it from your next take, and the keyboard the next time it appears.

- **Bars** is the classic equalizer.
- **Speckle** is a dust field that drifts when quiet and vibrates with your speech.

## What does the pill show on iPhone?

The pill in the keyboard shows where your take is. The screen murmur opens to shows the same pill while it records.

- **At rest**, it is small, grey, and still. It never shows amber at rest, even while a session keeps the microphone ready.
- **Recording**, it is wet amber at your voice's level, cooling toward gold as each moment ages.
- **Working**, the paint dries to gold with one sheen, and a softer sheen every 2 seconds if it takes a while, so a long wait never looks frozen.
- **Words added**, it sinks flat.
- **Heard nothing**, it is a dry grey scrape.
- **Failed**, it is plain red. Open murmur to see why and retry.

Your iPhone gives a light tap when a take starts and when it stops. With Reduce Motion on (Settings, then Accessibility, then Motion), each stage is a still picture. VoiceOver reads the pill as a button with its stage: Start dictation, Recording, Working, Words added, Heard nothing, or Failed, retry in murmur.

## How do I set up murmur on iPhone?

Open murmur once; it walks you through four steps and a practice take. Each step says why murmur needs it, and any step can be skipped. What you skip waits on murmur's home screen under Finish setting up.

1. **Allow the microphone.** Tap Allow the microphone, then Allow. If you said no before, tap Open Settings and turn on Microphone.
2. **Add the murmur keyboard.** Tap Open Settings, tap Keyboards, turn on murmur, then turn on Allow Full Access and tap Allow. Come back, tap the box, and pick murmur with the globe key: with Full Access on, the keyboard tells murmur it is ready, and this step and the next check themselves. If you leave Full Access off for now, tap I added it.
3. **Turn on Full Access.** If you left it off, the same place in Settings has the switch; come back and tap the box as above. The keyboard sends nothing anywhere and only types the words you dictate.
4. **Add your key.** Pick who transcribes and paste your key. See How do I add my API key on iPhone?
5. **Try your first take.** Tap the box, pick murmur with the globe key, tap the pill, say a sentence, and tap the pill again. Your words land in the box.

In other apps, when no session is running, your first tap opens murmur. Swipe right along the bottom edge to go back, and keep talking.

## Where is my history kept on iPhone?

Only on your iPhone, in murmur's own storage. Your history is left out of iCloud backups and never goes to your provider or anyone else. The murmur keyboard never sees it: only your newest take's words pass through the drawer the keyboard shares, cleared as soon as they are typed or when you delete that take. Because your history is left out of backups, it does not move to a new iPhone.

murmur's home screen shows your takes, newest first, with their words, when you spoke them, and how long they ran. Tap a take to copy its words.

## How do I delete my history on iPhone?

On murmur's home screen, swipe left on a take and tap Delete, then Delete take. To delete everything, tap Clear all above your takes; murmur asks first and says how many takes will go. Deleting murmur from your iPhone deletes your history too.

## How do I teach murmur a word on iPhone?

In murmur, tap the gear at the top right, then Dictionary and expansions. Under Words, tap Add. In When murmur hears, type what murmur writes wrong (la broy), and in Write it as, type it your way (LaBroi), then tap Save.

murmur writes the word your way wherever you say it, with your casing kept even at the start of a sentence. It also offers your provider the spelling as a hint, so a speech model that takes hints gets it right more often to begin with. A provider that refuses the hint still hears your take, just without it. Tap a word to change it; swipe left on it to delete it, and murmur asks first.

## How do expansions work on iPhone?

An expansion turns a short thing you say into longer text. In murmur, tap the gear, then Dictionary and expansions. Under Expansions, tap Add, type the trigger (my address) and the text (1 Main Street, Springfield), and tap Save. Say the trigger on its own or in a sentence, and murmur writes the text in its place. Expansions run last, after cleanup, so the text comes out exactly as you typed it.

## How do I send diagnostics from my iPhone?

In murmur, tap the gear at the top right, then Diagnostics, then Save report. murmur shows you the whole report first. Tap Share to send it by Mail, Messages, or any app you choose, or tap Done to keep it to yourself. murmur never sends a report by itself.

The report is one plain text file. It holds the murmur version, your iPhone model and iOS version, whether the murmur keyboard has reported with Full Access, your session length, your settings as names and counts (your provider and models, how many dictionary words and expansions you have, whether a key is saved; a model id you typed in yourself shows only how long it is), and the recent activity log.

The activity log is one short line for what happened to each take: captured with its loudness, heard nothing with its loudness, failed with the kind of failure and its error number, cancelled before it was sent, the number of words it came back as, and whether the keyboard typed the words or offered them as Insert last. It never holds your words, your dictionary or expansions, a custom provider address, or your key. It stays in murmur's own storage on your iPhone, out of iCloud backups, and keeps only its most recent lines: at most 128 KB, a couple of thousand lines, with older lines dropped.

## How do I start murmur from Control Center or the Action Button?

murmur has a control called Start murmur. One tap starts a session without opening murmur: the microphone is ready, so a tap on the murmur keyboard's pill in any app starts a take at once.

- **Control Center:** open Control Center, touch and hold an empty spot (or tap the plus at the top left) to edit it, tap Add a Control at the bottom, and pick Start murmur.
- **Lock Screen:** touch and hold the Lock Screen, tap Customize, then Lock Screen. Tap the minus by one of the two controls at the bottom, tap the plus, and pick Start murmur.
- **Action Button:** open Settings, then Action Button, swipe to Controls, tap the button under it, and pick Start murmur.
- **Shortcuts:** murmur adds Start a murmur session and End the murmur session to the Shortcuts app.

These steps follow Apple's iPhone User Guide, checked 2026-10-13.

The first time, open murmur once and allow the microphone: a control has no screen to ask from, so until then Start murmur starts nothing. Starting this way also needs Live Activities on for murmur (Settings, then murmur, then Live Activities), because iOS keeps the microphone for a session started from a control only while murmur shows one. In Shortcuts, Start murmur says why when it cannot start.

## What does murmur show on the Lock Screen?

While a session runs, murmur shows a Live Activity on the Lock Screen and in the Dynamic Island: the pill, Ready or Recording, the time left in the session, and End. iOS redraws it only now and then, so the pill there stands still and never moves with your voice; the keyboard's pill is the one that listens. End there ends the session at once. If you turn off Live Activities for murmur, a session you start in murmur or from the keyboard still runs as usual; only Start murmur needs them.

If murmur closes while a session runs (you swipe it away, or iOS stops it), the session ends and the orange dot goes out. The Live Activity can stay a while; once its time runs out it says Ended. Tap End or open murmur to clear it.

## How do belts work on iPhone?

The same way as on the Mac: the same ladder of belts and stripes (white, blue, purple, brown, and black, each with four stripes, then the black belt degrees, the coral belts, and the red belt), with the same two gates for each. A belt needs both enough words dictated and enough different days you dictated on, so one long day never skips a belt. What every belt and stripe takes is in the [Journey guide](../../docs/journey.md), under What are the exact requirements for each belt and stripe?

On iPhone, the Journey row on Home shows your belt. Tap it to see your stripes, your words and your days against what the next belt needs, your level (one more for every hundred thousand words), and the day you earned each belt.

Your iPhone counts only the takes it keeps in its own history. Deleting takes there lowers your count, as clearing history does on the Mac. For now your iPhone and your Mac each keep their own belt; one Journey across your devices comes with the murmur account.
