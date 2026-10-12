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
