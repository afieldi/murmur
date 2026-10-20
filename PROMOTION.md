# Promoting murmur

A living list of where and how to put murmur in front of people. New ideas go in the inbox at the bottom. When one is worth doing, move it into a section; when it is done, log the date and what moved.

## Where we start

Baseline on 2026-10-19, from GitHub's release counts: 72 installer downloads (Mac and Windows, every release since launch on 2026-09-08, some of them our own) and 1 star on the repo.

Already built and ready to promote with:

- The site, https://murmurapp.app, with the paint-it-yourself hero, the poster, and the 15-second film "One drop"
- The Wispr Flow comparison page, https://murmurapp.app/wispr-flow-alternative/
- The docs, written to answer the questions people search for
- Share cards (the belt card and the painting card), each carrying murmurapp.app

## What we say

**One sentence:** murmur is free, open source push-to-talk dictation for Mac and Windows. Hold a key, speak, and your words land at your cursor.

**What sets it apart:** an open source Wispr Flow alternative with no account, no subscription, and no weekly word limit. Your audio goes only to the provider you pick, including a Whisper server on your own computer.

**Rules for every post:**

- murmur is always lowercase.
- Claims about other apps come from their own pages, with the date checked, the way the comparison page does it.
- Never ask anyone for upvotes or stars. Say plainly that we built it.

## Quick wins

1. Point the GitHub repo's website field at https://murmurapp.app (today it points at the README), and add topics people search for, such as wispr-flow-alternative, voice-typing, open-source, and macos-app.
2. Bing Webmaster Tools: import murmurapp.app from Google Search Console. ChatGPT's search leans on Bing's index, so this is how murmur shows up there.
3. AlternativeTo: list murmur as an alternative to Wispr Flow. People browse these lists, and answer engines read them.
4. Curated Mac app lists on GitHub: open a pull request adding murmur to lists such as serhii-londar/open-source-mac-os-apps and jaywcjlove/awesome-mac, after reading each list's contribution rules.

## Launch posts

One at a time, about a week apart, so each one gets full attention and we can see what it moved.

1. **Show HN on Hacker News.** The title starts with "Show HN:" and names something people can download and try today, for example "Show HN: murmur, open source push-to-talk dictation for Mac and Windows". Stay for the first few hours to answer comments.
2. **Reddit.** r/macapps first, then r/opensource. Read each subreddit's self-promotion rules before posting.
3. **Product Hunt.** Save it for the iPhone launch (IOS-026), when murmur is on Mac, Windows, and iPhone, and use the film as the gallery video.

## Video

1. **The Technical Marketer.** The build story is as much the hook as the app: a marketer who builds his own apps with AI, and a free Wispr Flow alternative that came out of it. Link the site in the first line of the description.
2. **Shorts, Reels, and TikTok.** The film, plus 30-second screen recordings of one real moment each: a brain dump sorting itself into todo.md, a painting a day filling in, a belt promotion.

## Written posts

1. **LinkedIn.** The build story for a network of people who type all day.
2. **X.** Short clips from each release, linking the changelog page once it ships (US-106).

## Built into the product

- Every shared belt card, painting, and poster carries murmurapp.app, so each share is a small ad. Idea: make sharing one click at the moments people are proud of, like a new belt or a finished painting.
- Every release gets a changelog section to link to (US-106).
- The iPhone App Store launch (IOS-026) is the next big moment: App Store search, plus Product Hunt.

## Later

- **Homebrew cask** (`brew install --cask murmur`). Homebrew asks for some popularity before accepting a new cask; revisit once the repo has more stars.
- **Paid ads.** Not until the hosted plan exists. A one-time sale can't reliably pay for ads.
- **Referral codes.** A discount for each friend who buys Pro.
- **Mac writers and newsletters.** Pitch them once there are users and a story to tell.

## How we measure

- **Installer downloads** (updates don't count):

  ```sh
  gh api repos/lbwalton/murmur/releases --paginate --jq '[.[] | .assets[] | select(.name|test("\\.(dmg|exe)$")) | .download_count] | add'
  ```

- **Search:** Google Search Console for murmurapp.app.
- **Stars** on GitHub, and **Pro sales** in Stripe.
- murmur collects nothing about its users, and the site has no analytics today. Adding privacy-friendly site analytics is LaBroi's call.

## Log

| Date | What we did | What moved |
| --- | --- | --- |
| 2026-10-19 | Baseline | 72 installer downloads, 1 star |

## Ideas inbox

- (new ideas go here)
