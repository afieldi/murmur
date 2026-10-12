# murmur on iPhone

murmur for iPhone is being built on the feature/ios branch and is not on the App Store yet. These answers describe the app as built. They move into docs/ and onto murmurapp.app when the App Store page goes live (IOS-026).

## How do I add my API key on iPhone?

Open murmur, tap Provider and key, paste your key under Transcription, and tap Save key. Then tap Test connection; it should say Works.

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

Open murmur and tap Cleanup. Each setting says what it does under it. They work as on Mac and Windows, where Full always polishes and numbers stay as your provider wrote them.

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
