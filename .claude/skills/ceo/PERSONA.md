# Vela — Early Adopter Personas

> **Status: WORKING HYPOTHESIS (adopted 2026-07-14, Daniel's research + web validation corpus in memory `market-validation-research-2026-07`).** Phase 1 interviews harden or break this document — update it with real users' names, quotes, and corrections as they arrive, and log persona-changing evidence in [STATE.md](STATE.md).

---

## PRIMARY — Maya R.: the growth-stage food/travel short-form creator

**Snapshot.** 24, Los Angeles. Freelance content creator + micro-influencer in food/travel. TikTok, IG Reels, YouTube Shorts. ~30k followers, goal 100k+ in 6–9 months. Posts 4–7 short-form videos/week. Style: fast cuts, punchy hooks, captions, B-roll overlays, review-style storytelling.

**Goals.** Building a personal brand around food reviews, travel clips, and "viral spots" in LA. Treats content like a part-time job — 10–15 hours/week across ideation, filming, editing. Wants to post more consistently without sacrificing quality or burning out. Comfortable with CapCut / Premiere Rush / in-app editors, but **editing is her biggest bottleneck**.

**Current workflow.**
- Shoots raw vertical 9:16 on phone — 1–3 min of talking + B-roll per video.
- Dumps into CapCut, manually trims silences and filler.
- **2–3 hours per video** picking the hook, cutting dead air, adding captions and B-roll. (Corroborated: r/SaaS creator "if you ever figure out how to make those 30-second videos in less than 2 hours, pls drop the secret"; r/Tiktokhelp "such a time consuming and laborious process, especially video editing".)
- Struggles to decide which parts are useful, which are filler, which opening is strongest.
- Exports and posts, then second-guesses whether the hook arrived early enough and the pacing is tight.
- Feels stuck between wanting to automate more and fearing loss of creative control.

**Pain points (each maps to a Vela surface).**
1. **Hook selection** — second-guesses the first 3–5 seconds, reorders the intro multiple times before posting. → hook picker / hookId.
2. **Segment decision fatigue** — hates staring at timelines deciding keep/cut/move. → Triage swipe deck.
3. **Time sink in trimming** — manually removing filler, pauses, low-energy sections feels repetitive. → dead-air detection in the plan.
4. **B-roll placement** — knows B-roll helps, struggles to time it to the right beats. → Polish B-roll lane.
5. **Caption timing** — adds captions but over-edits them.
6. **Workflow friction** — record → edit → revise → re-edit with no clear review process; it feels messy. → the plan IS the review process.

**Psychographics.**
- **Control freak, but time-poor.** Wants AI to help, not take over — wants to *approve decisions*, not receive auto-generated edits. (This is the sentiment-validated pattern: every praised AI editor is "AI proposes, human disposes"; every trashed one is a black box committing to wrong cuts.)
- **Performance-conscious.** Watches retention graphs and drop-off points but doesn't know how to systematically fix them. (The Read speaks to this — within the honesty model.)
- **Experiment-driven.** Tries new hooks/formats/styles; needs a faster way to test and iterate.
- **Tool-savvy but burned.** Already uses AI tools for captions/repurposing; finds them generic and autopilot. Pays for CapCut Pro resentfully post-price-hike ("they're hungry for money and hid everything behind a paywall" — r/CapCut); credit metering is an uninstall offense ("only 6 videos before they ask for more money" — Captions review).

**What she wants in the app.**
- **Segment-first view:** her video broken into meaningful chunks (hook, filler, highlight, B-roll moment), approve/cut each with one tap.
- **Hook suggestions:** 2–3 strong opening options with quick preview.
- **Swipe decisions:** approve/reject each segment like a deck of cards, not a timeline.
- **Smart pacing:** suggestions for where to cut silence, speed up, or add visual change to avoid drop-off.
- **B-roll cues:** clear markers for where overlay shots keep visual variety high.
- **Export-ready drafts:** clean, captioned, vertical export she can post with minimal extra work.

**Her metrics.** Time from raw footage → publishable draft; videos posted per week; retention at 3s and 10s; average watch time / rewatch rate; engagement per post.

**Her mindset, in one line:**
> "I want the editing part to feel like decisions, not a puzzle. If I can just approve what's good and cut what's weak, I can post more and stress less."

**Why she can pass the gate:** at 4–7 videos/week she hits fifth-video retention inside two weeks — if the first cuts are good.

**Open risk to test in Phase 1 (do not paper over):** Maya's income is the algorithm, not invoices — research shows her segment pays $8–20/mo but churns when novelty fades. Her retention depends on Vela becoming her *default* workflow, not a toy. Watch her cohort's fifth-video number against Sofia's (below).

---

## SECONDARY — Sofia: the client-paid food/restaurant UGC creator

Late 20s, mid-size food city, day job, LLC on the side. Makes short food videos *for clients* (restaurants, cafés, food brands) at $150–300/video, 4–8/month; ~3 hours of editing per video is the ceiling on taking more clients (r/UGCcreators: "1 30 second video takes me about 2 hours to script... 1 hour to film... about 3 hours editing"). Expenses her tools ("Membership to Canva, CapCut, etc" in UGC LLC tax threads). Cares less about virality, more about **client-ready output**: full-res, no watermark, her client's brand served, nothing she didn't approve shot-by-shot, cut footage never silently discarded (b-roll is billable). Clearest willingness-to-pay in the research — recruit her cohort in Phase 1 alongside Maya's and compare retention. If Sofia out-retains Maya, the positioning shifts to ROI ("get your editing hours back"); if Maya out-retains, it stays growth ("post more, stress less").

---

## TERTIARY — Tariq: the unpaid grinder (aspiring creator, $0 income)

19–23, student or entry-level day job. Posts food/lifestyle short-form **3–5x/week for free** — gifted meals, "exposure" collabs, or purely chasing growth from a few hundred followers. No income from content yet; that's the whole point — he's grinding toward being Maya. Ambitious, extremely active in creator communities (he's who actually answers Reddit threads and DMs back), edits in free-tier CapCut and felt the paywall creep hardest because he can't absorb it. **Same pains as Maya** (hook second-guessing, decision fatigue, dead-air trimming eating his nights around class/work) but near-zero willingness to pay — $6/mo is a real decision for him, $15 is a no.

**How to treat him:** a real early adopter and the loudest evangelist — recruit some in Phase 1 for feedback volume and word-of-mouth, and because today's Tariq is next year's Maya. But **never design the business around him**: he inflates signups and download counts while contributing ~$0 MRR, which is exactly the vanity-metric trap AI editors die in. Product implications: the free experience (trial/first videos) must be generous enough that Tariq can genuinely use and evangelize Vela, with the paywall placed where Maya/Sofia value lands (volume, style templates, client-ready output) rather than crippling the basics — but pricing decisions are made for Maya and Sofia, not him. In gate metrics, track his cohort separately so free-user enthusiasm never masks paid-retention truth.

---

## ANTI-PERSONAS — do not design for these (yet)

- **The hobbyist home cook** (posts 2x/month for fun): cooking is her bottleneck — "editing is the easy part" (r/InstagramMarketing food creator). Won't pay, can't retain. (Distinct from Tariq: he posts weekly with ambition; she posts monthly for fun. Frequency and intent, not income, is the line.)
- **The pro videographer** (desktop NLE, $800+ productions): mobile-first is a toy to him; Eddie AI serves him.
- **The anti-content chef:** hostile to making TikToks at all; occasionally Maya's collab or Sofia's client, never a user.
- **The agency/team** (accounts, collaboration, brand kits, review flows): real money, wrong phase — Phase 4 at the earliest. (Maya's "team review flow" wish lives here.)

---

## FEATURE MAP — persona wants vs. what's built

**MVP must-haves (Maya's list → status):**
1. Segment breakdown with timestamps + labels — ✅ built (Edit Plan → FirstCutView/Triage).
2. Hook picker with multiple options — ◐ partial (hookId selection exists; "2–3 ranked options with preview" is the gap — virality M1 territory).
3. Swipe-to-keep / cut / promote — ✅ built (Triage deck).
4. Automatic filler/dead-air removal suggestions — ◐ partial (DECIDE trims; surfacing them as *suggestions she approves* is the Maya-shaped framing).
5. Caption generation with keyword emphasis — ❌ parked (text overlays in virality backlog). Flag: this is on her MUST list — revisit priority at Phase 1 if testers confirm.
6. One-tap vertical export — ✅ built.

**Phase 2+ nice-to-haves (hers → our parked list):** B-roll recommendation engine (b-roll precision, parked); retention drop-off prediction (⚠️ only within the Read's honesty model — bands tied to real footage evidence, never simulated percentages); A/B hook testing (two exports — natural fit with virality backlog); revision notes/version compare; team review flow (Phase 4).

---

## THE MAYA TEST — design law for every feature and screen

Before building or changing anything, ask: **"Does this turn Maya's footage into a posted video faster, with every decision visibly hers?"** Concretely:

1. **Decisions, not puzzles.** Every editing surface should present an approvable decision (keep/cut/reorder/hook), not an open-ended timeline task. If a feature adds puzzle, it's a regression even if powerful.
2. **Speed to first cut is sacred.** Anything that delays import→reviewable plan (extra steps, slow uploads, blocking screens) hurts her posting cadence — the thing she's actually buying.
3. **Control is the trust contract.** AI proposes, Maya disposes: every decision inspectable (why this cut — evidence-tied), every decision reversible, nothing commits without her. Protect the HITL plan review and the Read's honesty model (bands, not fake percentages) from simplification passes.
4. **Her voice is the product.** Style features reproduce *her* — never impose a house look; signature lines are [slot] templates, not transcripts.
5. **Footage is never silently lost.** Cut clips stay reachable (footage-conservation rules are permanent law); for Sofia it's billable inventory, for Maya it's tomorrow's B-roll.
6. **Post-ready output.** Vertical, full-res, no watermark, export reliability > export features.
7. **Interruptible by design.** She edits in stolen hours — state survives backgrounding, long jobs notify, failures recover without data loss.
8. **Flat pricing is a product feature.** No credits, no meters, no surprise paywalls; engineering choices that would force metering are product regressions.
9. When Maya and Sofia conflict, **Maya wins** — until Phase 1 retention data says otherwise (then update this file). When Tariq conflicts with either, the payers win — but keep the free experience generous enough that he can evangelize.
