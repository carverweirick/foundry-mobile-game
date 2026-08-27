# Rangeview Foundry (working title)
### A hybrid idle / factory management mobile game

*Master document, merging the full design spec with the current implementation status pulled from the project's CLAUDE.md. This replaces the previous docs/design_doc.md.*

---

## 1. Concept Overview

**Elevator pitch:** You run an investment casting shop. Machines and cycles hum along on their own timers, but the real skill is knowing when to jump in, batch smart, and catch the moments that matter before a cycle breaks. Take a part from a printed pattern all the way to a finished casting shipped to a customer.

**Genre:** Hybrid idle/incremental + factory management sim
**Platform:** Mobile, landscape orientation (a deliberate choice, not a default left unquestioned - the shop floor's multi-room layout was always envisioned as a wide space to pan across, not a portrait one-handed screen)
**Purpose:** Personal hobby project

**Premise:** You're the new CEO of the company, until now a lab scale operation that had already mastered the fundamentals of investment casting, printing patterns, proper shell building, burnout, pour, the whole standard process, proven and repeatable, just never run at real commercial volume for outside paying customers. The founder's forward looking research was the next step past that, a self binding resin process meant to one day skip shelling entirely, validated only at small scale, never taken into real production. The board brought you in to scale the proven process into a real foundry serving real customers, while carrying that resin research forward rather than starting it from scratch.

This clarifies what "not losing sight of your roots" actually means: you're not learning to cast metal for the first time, the company already knows how. What you're building is the business side, customers, reputation, floor, staff, while carrying forward research nobody's finished yet. It also lines up cleanly with Geometry Familiarity, the standard process itself was never in question, what's genuinely risky is a specific unfamiliar geometry for a specific new customer, exactly what that system already models.

**Delivery:** a short intro, a few dialogue lines from the outgoing founder staying on briefly to hand things off, sets this up before the player touches a station. That same character then walks the player through their first Part's traveler card as the actual tutorial, then steps back. Story and onboarding are the same sequence, not two separate systems.

That first Part deliberately carries zero defect risk, regardless of the normal risk tables. It's framed as simple, well trodden work the company has already done a hundred times, not an arbitrary tutorial safety net, so a brand new player learns queuing, collecting, and routing without also having to learn the quality system in the same breath.

Once that first Part ships, a second contract introduces the first real trial, a new, unfamiliar geometry, with the founder's dialogue framing it plainly, something like "now we're doing something we haven't actually done before." This is the first contract where the real defect tables apply, and the natural first place a player encounters a flagged defect, a grace period, and a fix path. It's also the first real exercise of Geometry Familiarity starting at zero stars, so the tutorial and a core system land in the same moment rather than needing separate explanation.

**Tycoon pivot:** the project is deliberately leaning further into tycoon-style retention design on top of everything above, not replacing it - see Section 23. The working principle carried through that section: hands-on casting (queuing, batching, routing, diagnosing defects, choosing fixes) stays the satisfying core loop for signature and special-order work indefinitely, and automation via hired technicians (Section 7) is the reward for having proven a station out, not a way to make the tactile gameplay disappear. Concretely, that means being deliberate, station by station and system by system, about what should stay a manual, hands-on decision forever (Push Through calls, defect fixes, contract selection) versus what's fair game to hand off once a technician is staffed there (routine queuing and batching on a mastered geometry). The known risk, called out explicitly rather than left implicit, is that a late game with everything automated can start to feel like watching numbers go up instead of playing a game - Section 23's retention systems (live events, the collectible album, rolling login streaks) are partly there to keep giving a fully-staffed late-game player fresh reasons to jump back in and take an active hand, not just to pad session count for its own sake.

---

## 2. Core Loop

This is an idle first game. Every station runs on a timer, and mini games are not required to progress, they are an optional way to shortcut a wait, added later on top of the timer system.

**Background layer (idle):** Every station has a timer, for example a station might take 30 minutes. It counts down whether you are watching or not. Progress accumulates even when the app is closed, then you come back to a shop full of finished work waiting to move on.

**Foreground layer (active):** Your real decisions are queuing a part into a station, choosing batch size (how many patterns per UV cure run, how many shells per burnout load), and routing a finished part to its next station. No taps are required mid timer, just at the start and at handoff points.

**Optional layer (add later):** Instead of waiting out a timer, spend a resource or play a short mini game tied to that station to finish it instantly. This turns mini games into a "spend effort instead of time" option rather than a mandatory gate.

**A deliberate design guardrail, formalized in the tycoon pivot (Section 23.1):** progress while away should never feel worthless, that's the whole point of the background layer, but actively working a session should reliably out-earn the same stretch of time spent idle. The systems already in this doc do most of that work without needing a separate "idle efficiency penalty" bolted on: Push Through (Section 9) only grants its bigger familiarity jump to a part a player actively chose to push, a technician's multi-station walking penalty (Section 7) means an unattended floor runs measurably slower than one a player is actively directing, and diagnosing and fixing a defect within its grace period (Section 9) is strictly better than letting it sit. Idle Plus Active Hybrid, in other words, isn't a new system to build so much as a lens for checking that every future system keeps this gap intact rather than accidentally flattening it.

The loop, start to finish:
1. Queue a pattern to print, timer starts
2. Route the finished pattern into shell building once its timer completes
3. Set shelling batch size and coat count, timer runs
4. Route the finished shell to burnout
5. Route the fired mold to pour, then to post processing
6. Ship the finished casting, earn currency, spend it on upgrades that shorten timers or add parallel capacity

---

## 3. The Process, Mapped to Phases

**Phase 1, Print Room** *(revised this session, see Section 21)*
- Print the green body pattern on one of the player's purchased printers (idle timer). Collecting the finished pattern off the printer is the deplate action, there is no separate Deplate station
- Clean: remove excess resin (idle, batched)
- UV cure (idle, batched, enclosed so it does not affect anything else in the room)
- Structured light scan for quality check (quick active tap, catch defects early). A flagged printer defect never blocks the part or offers a decline option, it always proceeds to Patching
- Patching: every part passes through here, not just flagged ones. Auto-resolves any printer defect, outcome quality scales with the assigned technician's skill. Smooths surfaces and closes holes on every part regardless of defect status

**Phase 2, Shell Building**
- Attach pour cup (single part, timer)
- Shelling: build 8 to 14 coats (the shop's longest timer, see Station Mechanics below for tiered batching behavior). Late game, a fully developed self binding resin can skip this phase entirely for flagged parts, see Research and Development below

**Phase 3, Furnace Room**
- Burnout: fire the shell to remove the pattern material, leaving a hollow ceramic mold (idle, batched, long timer)
- Mold Prep: every part passes through here. Mortar Patch, for shell cracks from Shelling or Burnout, happens at this station

**Phase 4, Pour Room**
- VIM and pour: melt and pour metal into the shell (active, timing based)

**Phase 5, Post Processing**
- Deshell: break away the ceramic (active, quick breakaway action)
- Abrasive blast: clean up the casting (idle, batched)
- Ship to customer: completes the loop, pays out currency

---

## 4. Station Mechanics

*Table revised this session, see Section 21 for full rationale on every change below.*

| Station | Type | Player Action |
|---|---|---|
| Printing | Timer, multiple purchasable units, tier gates batching per printer | Queue a job on a specific printer |
| Clean | Timer, batched | Set batch size |
| UV cure | Timer, batched | Set batch size |
| Structured light scan | Timer, quick | Queue for inspection |
| Patching | Timer, auto-resolve, not batched | None, resolves automatically, quality scales with assigned technician skill |
| Pour cup attach | Timer, single part | Queue |
| Shelling | Timer, single part at Tier 1; parallel independent timers at Tier 2+ | Queue (Tier 1); load multiple parts, each running its own timer by coat count (Tier 2+) |
| Burnout | Timer, batched | Set batch size |
| Mold Prep | Timer, not batched | Queue; apply Mortar Patch here if the part has a shell crack |
| Pour | Timer | Queue, or Push Through a flagged part |
| Deshell | Timer, quick, no defect risk | Queue |
| Abrasive blast | Timer, single part at Tier 1; batched at Tier 2+, no defect risk | Queue (Tier 1); set batch size (Tier 2+) |
| Ship | Automatic | Pays out currency once a part clears blasting |

There is no standalone Deplate station. Collecting a finished pattern off a printer is itself the deplate action.

Every station follows the same shape: queue it, optionally set a batch size, then wait out the timer or route it once it completes. A mini game per station can be layered on top later, purely as an optional way to finish a timer early instead of waiting.

**Rack capacity vs. batch size, now two separate numbers per station (revised this session):** every station starts with a single rack slot, a small holding spot right next to the machine, imitating a desk rather than a real rack. As the player upgrades, that slot grows into an actual multi-slot rack. Rack capacity is how many parts can physically sit at that station waiting. Batch size is how many parts run together sharing one timer. These are independent purchases: a station can have a rack of several slots but still only batch a subset of them at a time, with the rest waiting their turn. Tier upgrades are also station-specific in what they actually do, not a single universal effect: printer tiers add per-printer batching, Shelling tiers add parallel independent timers rather than a shared batch timer, Abrasive Blast tiers unlock batching that does not exist at Tier 1, and other stations may simply speed up or eventually gain precision effects.

---

## 5. Shop Floor Layout

**Standard Shop Floor:** every new player starts on a preset floor modeled on a real shop layout, so nobody has to design anything before they can start playing.

**Layout, revised this session into a four-corners-plus-center arrangement** (design request: "print room top left, shell room top right, burnout bottom right, post processing in the bottom left, and then the VIM and air melter in the center"), replacing the previous scattered room placement:
- **Print Room** (top-left): Printing (multiple printer units), Clean, UV Cure, Structured Light Scan, Patching
- **Shelling Room** (top-right): Shelling, Pour Cup Attach
- **Furnace Room** (bottom-right): Burnout, Mold Prep
- **Post Processing Room** (bottom-left): Deshell, Abrasive Blast, Ship
- **VIM Bay** (center): Pour/VIM today, and eventually a second melting station - see "Air Melter" below. Replaces the old "Pour Room (High Bay)"/Casting Area pairing - Casting Area never held a station and is dropped from the layout entirely; the gantry-crane/high-bay flavor folds into this same central room instead of a separate one.
- **Hallway**: connects everything - implemented as one full-floor base layer under all five room zones rather than a hand-drawn spine-and-branch shape, since the four corners only meet the center at single pinwheel-style points, not shared edges

Anyone who doesn't want to design their own floor just plays on this from day one, with a reset to standard layout option always available if a custom layout stops working out.

**Room expansion, a future direction (not built yet):** the four corner rooms should eventually be expandable - buying more floor space in a corner to fit more machines for that room's process, tying directly into the Floor Editor's "room size sets capacity directly" rule below rather than being a separate system. The center VIM Bay is deliberately not one of the expandable rooms in this framing - it's the fixed hub the four corners grow around.

**Air Melter, a new station idea (not built yet):** an alternate melting method alongside VIM in the center room, unlockable at a later Factory Level (see Section 21.2's existing factory-level-gates-printer-count precedent - this would be a second thing Factory Level gates, once Factory Level actually has a way to rise past 1, which it currently doesn't - see Section 20 item 5). The idea as given: only certain specific geometries can be poured from the Air Melter, not a blanket alternative to VIM for everything - which geometries, and what tradeoff pouring via Air Melter offers (speed? cost? a different defect profile?) versus the existing VIM/Pour station, still needs its own design pass before this is buildable.

**The Floor Editor**, for anyone who wants to design their own:
- Grid based room and equipment placement, similar to a base building game
- Stations only fit their matching room, a Burnout furnace can't be dropped into the Print Room, keeping this a real puzzle rather than an anything goes sandbox
- Room size sets capacity directly, a bigger Furnace Room physically holds more furnace slots side by side, tying square footage straight into the batch cap upgrades already in the economy
- Some equipment is anchored once placed, the same real constraint as the cleaner sitting fixed next to the distiller, moving it later costs real time and money
- Hallway distance is a genuine mechanic, not decoration. The pattern room travel time upgrade already in the economy is literally about how far apart rooms are, so a badly designed floor measurably slows the whole shop down

**Camera and navigation:** the shop is one continuous open floor rather than a single scrolling strip. The camera can be dragged around freely to move between rooms, and zoomed out for a full floor overview or in for a close look at one room's stations, meant to feel like a small top-down city builder on a phone.

**Grid and station footprints:** the floor is meant to sit on a tile grid rather than freeform pixel placement, the concrete version of the Floor Editor's grid based vision above. Every station has a footprint, how many grid cells it occupies, standardized and kept small enough that multiple stations can eventually sit side by side in a room rather than each one claiming as much space as it does today. Every station also has a single fixed access point, one specific tile directly in front of its footprint, the exact spot an interaction or a technician's arrival actually happens. For a first pass every station faces the same direction (south, toward the camera), no rotation, which keeps the art simple, one facing per station type, while still giving pathfinding somewhere concrete to route toward instead of a station's center. As of Section 18, this is still design intent rather than what's actually running, stations are currently hand-positioned per room rather than placed on a real grid.

**Technician movement:** technicians should path along the grid to reach their assigned station's access point, routing around station footprints and other obstacles rather than cutting through them, using the grid's non-walkable cells (station footprints, walls) as pathfinding obstacles. What's actually built so far (Section 18) is real physical movement and pacing, a technician genuinely occupies a position and walks between assigned stations, but it's a straight line to each station's fixed position, not yet pathfinding around anything.

---

## 6. Menu System

A single button opens a menu overlay on top of the floor. The floor itself never pauses, every station timer keeps running in real time whether the menu is open or closed, this is a simplified lens on the same live data, not a separate paused screen.

Three tabs:

**Overview** — every station across every room, its current status (idle, running with time remaining, or ready and waiting for collection), all in one simplified list instead of needing to pan the camera across the whole floor to check on things.

**Awaiting Transfer** — Parts that have been manually collected off an unstaffed station and are now sitting in a holding inventory, waiting for a player decision on where they go next. A staffed station's technician collects and routes a Part in one motion the instant it's ready, so a staffed station's output never appears here, this tab is specifically the "only a human needs to deal with this" list.

**Contracts** — one row per active contract: customer, quantity required, quantity shipped, quantity currently somewhere in the pipeline assigned to it, and time left on the deadline.

**The manual flow this creates, for unstaffed stations:**
1. A station finishes running, the Part sits at the station, blocking new work from starting there
2. The player taps Collect at that station, freeing it up and moving the Part into the Awaiting Transfer holding inventory
3. The player assigns that Part to its next station, either from the Awaiting Transfer tab directly, or from that next station's own Batch Picker, both read and write the same underlying data so either entry point works

**The Traveler Card, a work order view for a single Part:** tapping any Part, from Overview, from Awaiting Transfer, or right off the floor, opens its own traveler card, borrowing the real shop floor's own term for exactly this. It shows:
- The assigned contract: customer, geometry, alloy
- A full vertical stepper of its route, every station in PIPELINE_ORDER listed top to bottom, each marked done, current with a live timer, or upcoming and grayed out. This is the vertical stepper layout from early in this doc, it turns out it belongs here, on one part's card, rather than trying to represent the whole floor at once
- A simple visual of the part's current physical state, a small reusable set of generic stage icons (green pattern, shelled mold, fired mold, raw casting, finished part) that swap based on pipeline position, shared across every geometry rather than needing unique art per part type
- A plain language "what's next" line at the bottom naming the next station directly

**Why this solves onboarding too:** a new player never has to understand every station and all 6 rooms at once. The first tutorial moment can simply be: make your first Part, open its traveler card, and follow that one card step by step through its whole journey. The rest of the floor is there to grow into, but the first five minutes only ever asks you to follow one card.

**The Shop button**, a separate overlay from the Menu, for spending currency rather than checking status. Everything in the Economy section's spending list (Upgrades, Alloy stock) belongs here as those systems get built, alongside:

**Technicians** — the hiring and staffing screen, deliberately not something you do one station at a time. Every technician you've hired, their skill tier, which station(s) they're currently assigned to, and the hire action itself all live here. See Technicians and Automation below for what happens after you've hired someone.

---

## 7. Technicians and Automation

This is what turns the "queue it yourself" foreground layer into a floor that runs itself, and it is also where the game gets its living, populated feeling.

**Unstaffed stations** need you. You start every game as the one person shop, manually queuing, batching, and routing every part at every station.

**Hiring** happens from the Shop's Technicians tab, not at a station. A hired technician exists on your roster whether or not they're currently assigned anywhere, the same way a held Part can sit in Awaiting Transfer without belonging to a station yet.

**Assigning** a technician to a station is a separate step from hiring, done by picking a technician and choosing the station(s) you want them working. Once assigned, that technician handles the queuing, batching, and routing there for you automatically, and shows up as a small animated figure at the station, visibly moving parts and working the equipment in real time. This is the visual heart of "watching your shop run."

**Skill tiers:**

| Tier | Hire Cost | Ongoing Wage | Effect |
|---|---|---|---|
| Apprentice | Low | Low | Automates the station at its baseline defect rate |
| Technician | Medium | Medium | Noticeably lower defect rate |
| Senior Technician | High | Higher | Lower defect rate still, faster reaction to flagged issues |
| Master | Highest | Highest | Lowest defect rate, and on some stations can safely run a bigger batch than an unskilled operator could manage |

Wages matter. This is not free automation, it is a genuine ongoing cost that has to be earned back through throughput, which keeps hiring a real economic decision rather than a one time unlock. Early game, a wage can eat meaningfully into a small contract's margin. Late game, the freed up attention and steadier defect rate are well worth it.

**Multi-station assignment and the walking penalty:** a technician isn't locked to one station forever, you can assign them to more than one. This is a real efficiency trade rather than a free multiplier: splitting someone's attention across stations means they're not standing at any single one full time, they're walking back and forth between them. Each additional station assigned to the same technician slightly reduces their effective productivity everywhere they work, representing the real time lost to movement (and this is exactly what a shorter hallway or a smarter floor layout would directly improve). A one-station technician is your most efficient use of a wage; a technician juggling three or four stations keeps more of the floor automated per person hired, but each of those stations runs a little slower than if it had someone dedicated. Late game, this becomes a real staffing puzzle: hire more people and dedicate them, or spread your existing roster thinner and accept the productivity hit.

**Technician inventory:** a technician working multiple stations needs somewhere to hold the Parts they're physically carrying between them, distinct from a station's own queue rack or the Awaiting Transfer holding inventory, both of which are things the player manages by hand. A technician's inventory is small and entirely their own, modeling "they're walking a finished Part from one station to the next right now," never something the player picks through directly.

**Station queue racks:** every station gets a small physical queue, not just the one in-progress slot. A technician can drop a finished Part onto the next station's rack even if that station is still mid-cycle on something else, and pick up from a rack the moment the station frees up, rather than the whole line stalling because one downstream step is running long. Rack capacity ties to the same batch cap upgrades that already grow a station's capacity, so a technician can still get backed up if a station falls far enough behind, it just gives the floor real slack instead of every station being a hard one-in-one-out gate.

**Keeping a Part's place in line:** with Parts now able to sit in a technician's hands, a station's queue rack, or the Awaiting Transfer inventory, each Part always needs to know two things: the last operation actually performed on it, and the specific next station it's headed to. This is what stops a Part from being dropped in at the wrong point in the process, skipping a step, or running through the same station twice, no matter which of those three holding spots it's currently sitting in.

**Routing strategy:** a technician working several stations chooses which one to head to next, once there's nothing left to do at the current one, based on a selectable working strategy - not a fixed cycling order:

- *Push parts through* - prioritize carrying a specific Part as far down the pipeline as it'll go, chasing it station to station rather than splitting attention evenly. Minimizes any one Part's total transit time; other assigned stations sit idle longer while this happens.
- *Maximize machines running* - prioritize whichever assigned station is currently idle with nothing in progress, to get as many machines running in parallel as possible. Maximizes overall throughput/utilization across the whole set; no single Part gets rushed.

This is a genuine behavioral choice, not just a speed setting, and different strategies suit different floor layouts and contract mixes - a rush order might call for "push it through," while a technician juggling several always-busy stations is better off "keeping everything fed." Switchable per technician from the Shop's Technicians tab at any time. A technician still only physically occupies one station at a time either way (see Multi-station assignment above) - the strategy only changes which station they choose to walk to next, not whether they can be in two places at once. Delivering anything they're already physically carrying always takes priority over either strategy's preference - there's no reason to walk past your own cargo's destination to go start a different machine.

---

## 8. Contracts

Contracts are the actual jobs that give production a reason to exist, and this is where the small to big, overlapping structure you described lives.

**Structure:** every contract specifies a customer, a geometry, a quantity, a deadline, and a payout. Bigger, later tier contracts also carry a reputation requirement to even see them offered.

**Tiers:**

| Tier | Customer Type | Quantity | Deadline | Payout | Unlocked By |
|---|---|---|---|---|---|
| 1, Local Shops | Small local businesses | 3 to 8 parts | Generous | Low | Available from the start |
| 2, Regional Manufacturers | Mid size companies | 10 to 25 parts | Moderate | Medium | Reputation threshold, a few Tier 1s completed |
| 3, Industrial Accounts | Larger manufacturers | 25 to 75 parts | Tighter | High | Higher reputation, solid Tier 2 track record |
| 4, Flagship Contracts | Big name, aerospace/automotive style customers | 75+ parts, often recurring | Tight, long running | Very high, plus ongoing repeat work | High reputation, several strong Tier 3 completions |

**Overlap:** multiple contracts run at once. Because Tier 3 and 4 contracts run long by nature (that many parts takes real time even with a fully upgraded shop), a big flagship contract is naturally still grinding away in the background while you take on smaller, faster Tier 1 and 2 jobs on the side. Stations are shared, so when you or your technicians queue a batch, that batch gets assigned to a specific contract, letting the floor interleave work across jobs rather than only ever running one thing at a time.

**Reputation:** finishing contracts on time with a low defect rate raises your reputation, which is what unlocks access to bigger customers. Missing deadlines or shipping too many defective parts lowers it, and can lock you out of the good contracts for a while. This gives real stakes to the quality and diligence systems below, since a bad run does not just cost you that one contract, it costs you future ones too.

**Randomized contract generation:** company names and the part/alloy work they need are two fully separate pools, rolled independently rather than fixed pairs. The same company name can show up needing something completely different next time. Shop-wide Reputation still gates which overall tier of companies can appear at all.

**Repeat clients:** every time a new contract is rolled, there's a base chance (roughly 20% to start) it pulls a company already worked with instead of generating a brand new name, and that chance rises the better relationships are going overall. Completing a contract well with a brand new company also raises the odds that name sticks around as a recurring face rather than fading back into a one-off.

**Per-Company Relationship**, separate from shop-wide Reputation: a 0 to 5 star score per company, tracking their specific history, rising on time and low defect deliveries, stalling or dropping on late or defective ones. A high relationship means: better odds they return with a new offer, bigger quantities, better payouts, and at 5 stars a chance they offer something a tier above what general Reputation would normally unlock. A maxed relationship can eventually become a standing recurring contract, the same flavor as the flagship recurring deals, just earned through relationship instead of handed out by default at Tier 4.

**Tycoon pivot pacing note:** this tier structure is also this game's answer to "Contract and Reputation-Based Progression" from the tycoon pivot notes (Section 23.4) - the short-deadline, small-quantity Tier 1 jobs and the long-running, high-quantity Tier 3/4 jobs already are the early-short-session to late-long-session pacing curve that pivot calls for, nothing new needed structurally, see Section 14 for the session-length targets that pin down.

---

## 9. Quality, Defects, and Geometry Familiarity

This is the system that makes new work feel genuinely risky, and rewards you for having solved a geometry before, exactly what you described.

**Real defect categories**, used for flavor and for the specialist system below:

| Defect | Shows up at | What it means |
|---|---|---|
| Shell crack | Shelling, burnout | Coats cured unevenly or dried too fast |
| Warping | Printing, burnout | The pattern shifted before or during firing |
| Porosity | Pour | Trapped gas left a weak spot in the casting |
| Misrun | Pour | Metal did not fully fill the mold cavity |
| Inclusion | Pour, post processing | Foreign material got caught in the casting |

**Base defect risk** (Tier 1 equipment, brand new geometry, no technician or an Apprentice running the station). **Revised this session: defects can only occur at these four stations.** Deshell and Abrasive Blast carry no defect risk at all, they are purely mechanical steps once a part reaches them:

| Station | Base Risk | Likely Defect |
|---|---|---|
| Printing | 5% | Warping, dimensional non-compliance, holes. Always resolved automatically at Patching, never a player decline point |
| Shelling | 20% | Shell crack |
| Burnout | 15% | Warping, shell crack. An unfixable Burnout defect means the part cannot become a compliant shippable part, it is kept only as a familiarity trial |
| Pour | 20% | Porosity, misrun. Some Pour defects can be salvaged afterward in Post Processing via grinding, depending on the specific defect |

Shelling and pour carry the highest risk since those are your real world trouble spots. Printing risk is resolved automatically downstream and never asks the player to decide anything.

**What brings that risk down, and stacks together:**

| Familiarity | Multiplier |
|---|---|
| 0 stars, brand new | 100% of base |
| 1 star | 80% |
| 2 stars | 60% |
| 3 stars | 40% |
| 4 stars | 20% |
| 5 stars, mastered | 10%, never zero |

| Technician Skill | Multiplier |
|---|---|
| Manual or Apprentice | 100% |
| Technician | 85% |
| Senior Technician | 70% |
| Master | 55% |

A specialist engineer applies one more multiplier, roughly 50% off, but only against their specific defect category, permanently once hired.

Worked example: shelling on a brand new geometry with nobody staffing it sits at 20%. Late game, a 5 star familiar geometry, run by a Master technician, with a Shell Specialist on staff, works out to 20% times 10% times 55% times 50%, under 1%. Genuinely risky early, genuinely safe once mastered.

**Diagnosis and the grace period:** a defective part gets flagged right on the floor view the moment it happens, with a defect category attached.

| Station | Grace Period |
|---|---|
| Printing, scan, deplate, cure, pour cup, deshell, blast | 30 min |
| Burnout | 40 min |
| Shelling | 45 min, since it is already the longest process |
| Pour | 20 min, tightest window since pour problems compound fast in reality |

**Escalation if ignored past the grace period:**
1. The defect starts to risk contaminating the rest of that batch, a rolling chance the other parts pick up the same issue
2. If it ships anyway, or sits long enough that it ships, the reputation hit lands on the contract and the part does not count toward the order, so the time and money already spent on it is lost

**Fixing it, three paths:**
1. **Patch it with mortar, shell cracks only.** *(Revised this session: this now happens at the Mold Prep station, which every part passes through after Burnout, rather than as a free-floating action.)* Apply mortar directly onto a cracked shell before it goes to pour. Quick, cheap, and reliable, this saves that specific part. It is a patch, not a fix, so it does not build familiarity, since the underlying cause was never addressed.
2. **Redesign it yourself.** Spend time and money adjusting the geometry (adjusting wall thickness, adding a fillet, that kind of choice), then run it back through the pipeline to confirm the fix actually worked. This is what raises familiarity.
3. **Bring in a specialist engineer.** A hire distinct from station technicians, tied to a defect category rather than a station.

| Specialist | Fixes | Effect |
|---|---|---|
| Shell Specialist | Shell cracking | Big permanent reduction to shell crack risk across all future geometries |
| Pour Specialist | Porosity, misruns | Reduces those defect types shopwide |
| Pattern Specialist | Warping | Reduces warping risk, especially valuable on new or complex geometries |

**Push Through, testing new parameters (significantly expanded this session):** a defective part is never scrapped or held back from proceeding just because it has a flaw, not even a dimensional non-compliance or a hole from a defective print. There is no player decline option at Scan. Real-world manufacturing does not scrap a first-article part for being imperfect either, the whole point of a trial is learning what breaks and why. Pushing a flagged part forward raises familiarity at each relevant downstream station based on what that station's parameters teach:
- **Shelling parameters** familiarity
- **Burnout parameters** familiarity, may lead to a real redesign such as adding vent holes or changing the part's orientation off the printer
- **Mold Prep parameters** familiarity, e.g. whether insulation is needed for pouring
- **Pour parameters** familiarity, e.g. pour temperature, or a resource choice like pouring in revert metal from previous trial pours instead of fresh alloy

Normal defect odds apply at each of those stations regardless of push-through status, but a push through always grants a bigger familiarity jump than a normal completed part would at that station, win or lose, since deliberately testing teaches you faster than the safe route. It still costs the part on certain failures (an unfixable Burnout defect, for instance), the same real risk as the resin experimental prints in the R&D system.

**The one case where not proceeding makes sense:** if the player already has very high familiarity with a geometry and can predict, with confidence, that a specific part will not meet a customer's tolerance, there is no point spending the cycle. This is the only scrap-before-shipping decision in the game, and it deliberately requires expertise to access, a brand new geometry is never something the player is expected to judge this way.

**Geometry familiarity, now per-station, the payoff for repeat work:** every geometry (or geometry family) starts at zero familiarity the first time you see it. *(Revised this session: familiarity is no longer a single score.)* A part builds up to four separate familiarity values for its geometry, one each for Shelling, Burnout, Mold Prep, and Pour, since those are genuinely different skills to develop. Redesign fixes, resolved specialist visits, and push through attempts all raise the relevant station's familiarity. At high familiarity, defect risk at that station drops to a low, reliable floor. A geometry a player has fully mastered across all four becomes an easy, safe, fast yes even at a smaller payout. A totally novel geometry stays a real gamble, riskier and slower at every station, but often the only way to unlock new geometry families and the bigger contracts that need them.

**Displaying familiarity:** a part shown in any menu displays a single average familiarity as a star rating, a quick-glance summary across all four per-station values. Press-and-hold on the part opens a detailed view breaking familiarity out by station. When the player is asked whether to proceed with a part that has a defect, the prompt also surfaces the single weakest-link station's familiarity as a percentage, since that is the number that actually matters for judging the specific risk in front of them.

---

## 10. Example Geometries and Starting Contracts

Putting real examples on top of the systems above, so there's something concrete to prototype against.

**Geometry families**, with a complexity rating that governs how many successful fixes it takes to fully master (reach 5 star familiarity):

| Family | Example Part | Complexity | Fixes to Master |
|---|---|---|---|
| Decorative | Pendant blanks, small decorative castings | Low | About 3 |
| Bracket | Mounting brackets, simple structural brackets | Low | About 3 |
| Valve | Valve bodies, valve handles | Medium | About 6 |
| Housing | Pump housings, gear housings | Medium | About 6 |
| Impeller | Pump and blower impellers | High | About 10 |
| Manifold | Hydraulic manifolds | High | About 10 |
| Turbine | Turbine blades, aerospace brackets | Very High | About 15 |

Families with related shapes share a partial familiarity carryover, roughly 50%. Mastering a Pump Housing at 5 stars gives a real head start (something like 2 to 3 stars worth) on a later Gear Housing contract, since it's a related but not identical shape within the same Housing family.

**Alloys**, roughly matched to contract tier:

| Alloy | Typical Tier | Relative Cost |
|---|---|---|
| Bronze | 1 | Cheap |
| Mild Steel | 1 to 2 | Cheap |
| Cast Iron Blend | 2 | Moderate |
| Stainless Steel | 2 to 3 | Moderate |
| Alloy Steel | 3 | Moderate to high |
| Nickel Superalloy | 4 | Very expensive |

**Starting contracts**, the first few a new player would see:

1. **Local Hardware Co.**, Tier 1. 5 Mounting Brackets in mild steel, generous deadline, small payout. The tutorial contract, brand new geometry and a brand new player, meant to walk the whole pipeline through by hand once.
2. **Riverside Jewelers**, Tier 1. 8 decorative pendant blanks in bronze, offered alongside the first contract so there's a real choice of what to start with, or both can run at once once queuing feels comfortable.
3. **Cascade Fluid Systems**, Tier 2. 15 Valve Bodies in stainless steel, the first taste of a bigger job, and likely the point where hiring a first technician starts to make sense.
4. **Northline Pumps Inc.**, Tier 2. 20 Pump Housings in cast iron blend, establishing the Housing family for the payoff below.

**A later payoff, once the Housing family is underway:**

5. **Summit Industrial Group**, Tier 3. 40 Gear Housings in alloy steel. Because this reuses the Housing family, a player who already mastered Pump Housings gets a real head start here, exactly the pull toward familiar work you wanted.

**A flagship example, for later in the game:**

6. **Meridian Aerospace**, Tier 4. 120 Turbine Blades in nickel superalloy, running as an ongoing recurring contract. High reputation required, a very high payout, expensive alloy, and the kind of job that sits in the background for a long stretch while smaller Tier 1 and 2 work keeps the shop moving day to day.

---

### Aerospace Contract Pool

Once contracts are being pulled from a bigger pool instead of just the starting six, here's a mix and match set leaning specifically aerospace, since that's naturally where the flagship end of the game lives.

**Company names**, grouped loosely by scale:

Small independents (Tier 1 to 2 flavor):
- Ironwing Fabrication
- Truenorth Precision
- Sparrowhawk Tooling
- Redline Machine Works
- Halcyon Components

Mid-size suppliers (Tier 2 to 3):
- Vantage Aerostructures
- Solstice Precision Manufacturing
- Ferrolux Industrial
- Apex Airframe Supply
- Cascade Fluid Systems and Cascade Turbomachinery (already in the starting six)

Flagship primes (Tier 4):
- Meridian Aerospace (already in the starting six)
- Altair Aerospace & Defense
- Zenith Dynamics
- Constellation Aerosystems
- Ironclad Aerostructures
- Skyforge Industries
- Pinnacle Aeroworks

**Part types**, organized by existing geometry family, plus two new families worth adding:

- Bracket family: engine mount brackets, avionics mounting brackets, actuator support brackets
- Valve family: bleed air valve bodies, fuel shutoff valve bodies
- Housing family: bearing housings, sensor housings, actuator housings
- Impeller family: compressor impellers, fuel pump impellers
- Manifold family: fuel manifolds, bleed air manifolds
- Turbine family: turbine vanes (nozzle guide vanes), alongside the turbine blades already established
- New, Strut family: landing gear struts, actuator linkages, complexity similar to Impeller
- New, Seal family: seal rings, diffuser rings, complexity similar to Valve

**Alloys**, expanding the existing table with more aerospace-specific options:

| Alloy | Typical Tier | Relative Cost |
|---|---|---|
| Aluminum alloy | 1 to 2 | Cheap |
| Titanium alloy | 2 to 3 | Moderate to high |
| Stainless steel, precipitation hardening grade | 2 to 3 | Moderate |
| Maraging steel | 3 to 4 | High |
| Cobalt-based superalloy | 4 | Very expensive |

(sits alongside the Bronze, Mild Steel, Cast Iron Blend, Alloy Steel, and Nickel Superalloy already listed above)

**A few more fleshed out examples, mixing all three:**

7. **Sparrowhawk Tooling**, Tier 1. 6 avionics mounting brackets in aluminum alloy, generous deadline, small payout, a second easy Tier 1 option alongside Local Hardware Co. and Riverside Jewelers.
8. **Ferrolux Industrial**, Tier 2. 18 bearing housings in stainless steel, another entry into the Housing family alongside Pump and Gear Housings.
9. **Vantage Aerostructures**, Tier 3. 35 compressor impellers in titanium alloy, the Impeller family's entry point.
10. **Altair Aerospace & Defense**, Tier 3. 25 landing gear struts in maraging steel, introducing the new Strut family.
11. **Zenith Dynamics**, Tier 4. 90 turbine vanes in cobalt-based superalloy, a second long running flagship contract overlapping in the background alongside Meridian Aerospace's turbine blade order.
12. **Constellation Aerosystems**, Tier 4. 60 fuel manifolds in nickel superalloy, recurring, another flagship option besides Meridian.

---

## 11. Economy and Progression

**Currency:** earned by completing contracts, paid out as parts within that contract are shipped.

**Where it goes, three ongoing buckets:**

- **Upgrades**, one time spends on faster or bigger stations:
  - Faster cure ovens, bigger cure batches
  - A second shelling rack (raises your WIP ceiling above the real world's 12 part cap)
  - A shelling speed up discount, once mini games are added, since shelling will always be the shop's single biggest time sink
  - Reduced pattern room travel time (an upgrade that visually shortens the walk animation between Print Room and Furnace Room)
  - A second scanner, a second pour station, and so on

- **Wages**, ongoing, for every technician and specialist engineer on staff (see Technicians and Automation, and Quality, Defects, and Geometry Familiarity above)

- **Alloy stock**, ongoing, purchased in batches ahead of a pour run. Different alloys cost different amounts, and the specialty alloys the bigger contracts call for cost noticeably more than the basics you'll use early on. Running out mid run stalls the Pour station until you restock, so keeping enough on hand is its own small piece of resource management.

**Meta arc:** you start as a one person shop doing everything by hand and manually catching every timer. As you hire technicians, background automation takes over the repetitive batched steps, and your attention narrows to the moments that actually need a human: diagnosing defects, deciding fixes, managing alloy stock, and choosing which contracts to take. Late game becomes about sequencing upgrades, managing reputation, and running several contracts at once rather than babysitting every station.

---

## 12. Research and Development

A passive, long tail system that runs in the background and eventually lets you develop a self binding resin, a pattern material that binds itself into ceramic during burnout, skipping shelling entirely. Print goes straight to burnout, straight to pour. This is meant to land very late game and should never replace the core loop of running every station, it is a reward for having already mastered it.

**Unlocking the R&D Lab:** the lab itself does not appear until well into the game, something like after shipping your 200th casting. Before that point there is nothing to spend on and no reason to think about it, keeping the early and mid game focused entirely on running the floor.

**Funding it:** once unlocked, the R&D meter fills two ways at once, matching what you described.
- **Extra time:** it ticks up slowly on its own in the background, whether you are actively playing or not, representing quiet ongoing experimentation
- **Extra money:** at any point you can dump surplus currency into the lab to add a lump of progress immediately, for players who would rather spend their way there

Neither path is required. A patient player gets there for free eventually, a well funded one gets there sooner.

**Tiers:**

| Tier | Unlocks | Rough Cost |
|---|---|---|
| Lab unlocked | R&D Lab becomes available | After ~200 castings shipped |
| 1, Early Formula Concepts | Flavor and lore only, no gameplay effect yet | Baseline |
| 2, Stable Compound | Small passive reward, roughly -5% off every shelling timer shopwide | 2x Tier 1 |
| 3, Early Prototype Resin | **Experimental Print** unlocked, see below | 2x Tier 2 |
| 4, Refined Prototype | Experimental success chance improves, failures become partially salvageable | 2x Tier 3 |
| 5, Stable Self Binding Resin | Permanent resin print option, fully reliable, skips shelling for good | 2x Tier 4 |

**Experimental Print, the mid game piece:** once Tier 3 hits, you can flag any print job as experimental. It skips straight from printing to burnout, no shelling at all. At Tier 3 it succeeds about 20% of the time, at Tier 4 that rises to around 40%. A failure destroys the pattern, so it is a real gamble, but every failure also feeds bonus research progress back into the lab, so even losing a part is technically useful data. This is exactly the "you've developed a resin that might work" feeling, a real but risky shortcut you can choose to take on individual parts well before the full unlock.

**Tier 5, the payoff:** the self binding resin becomes a standard, reliable option you can flag on any print job going forward, permanently skipping shelling for that part. This is the moment the station you have spent the entire game fighting and upgrading finally becomes optional.

**Design note:** this stays a parallel option, not a replacement. Worth giving the resin path its own throughput limit (a binder stock you have to keep producing, or a resin printer that runs slower than your main volume needs), so even a fully upgraded shop still runs standard shelling for most of its parts. The main game stays running the foundry end to end, resin printing is a powerful tool you get to use on some of your parts, not a way to skip the game.

---

## 13. Translating Real Constraints into Game Design

- **The cleaner is anchored next to the distiller and cannot move.** In game, certain equipment is fixed in place, so layout puzzles come from working around fixed stations rather than freely placing everything.
- **The Print Room is UV free.** Small flavor detail, and a soft justification for why UV cure has to happen in its own enclosed step rather than out in the open.
- **Batched vs single part operations create uneven work waves.** This asymmetry is the reason the idle and active layers exist side by side. Batching smooths the background layer, single part steps are where you tap.
- **Shelling tech is at full capacity.** In game, shelling gets the shop's longest timer and its tightest batch cap. That makes it the single most valuable place to eventually spend a speed up, whether that is currency or, once added, a mini game.

---

## 14. Session Feel

- **Early game:** timers are short and batch caps are small, you are staffing your first stations by hand, and every geometry is brand new, so defect risk is high and check-ins matter constantly. Busy on purpose, mirrors the real inefficiencies you have mapped out. Target session length is short, roughly **5 to 15 minutes** - a player should be able to fully work a Tier 1 contract or two, then put the phone down.
- **Mid game:** technicians are running the routine stations, but new contracts and unfamiliar geometries still demand real attention. This is where the diagnose and fix loop lives, and where ignoring a flagged defect actually costs you time, money, and reputation. Sessions start stretching past the early-game floor as Tier 2 contracts and their longer deadlines come online.
- **Late game:** familiar geometries run themselves reliably, upgrades have stretched batch sizes and shrunk timers, and the game becomes more about which contracts to take, which specialists to hire, and how the R&D resin path fits into the mix, rather than watching every part. Target session length grows to roughly **20 to 40 minutes**, mirroring standard mid-core tycoon pacing - a player is now juggling several overlapping Tier 3/4 contracts at once (Section 8's overlap structure), checking in on live events (Section 23.2), and clearing daily quests (Section 23.3), not just watching one job through.

This early-short to late-long pacing curve is a deliberate tycoon-pivot target (Section 23.4), not just an emergent side effect of bigger contracts taking longer - it's the same shape Section 8's contract tiers already produce (Tier 1's "generous" deadlines and small quantities versus Tier 3/4's "tight, long running" ones), restated here explicitly as a pacing goal to hold future contract-tier tuning against.

---

## 15. UI Direction

A vertical stepper showing each part's progress through the five phases fits naturally here, gated so a part cannot visually skip ahead until its current step's timer completes. Parts sitting in shelling could get a distinct highlighted state since it is the shop's longest running station and the one most worth watching for an available speed up. Staffed stations should show a small animated technician actively working, both for the "living floor" feeling and as a quick visual cue for which stations are automated versus which still need you. A flagged defect should stand out clearly from everything else on screen, since noticing it quickly is the whole point of the grace period.

---

## 16. Art Style

**Direction:** pixel art, retro feel, closer to something like Stardew Valley or Moonlighter than an 8-bit NES look, detailed enough to read clearly on a phone screen but unmistakably retro.

**Resolution:** aim for roughly 16x16 to 32x32 tile density. Enough detail to make each station and technician recognizable at a glance, still small enough to keep the art workload realistic for a solo hobby project.

**Room palettes**, since each phase already has its own real world character:
- Print Room: clean, cool whites and light blues, sterile and quiet
- Shell Building: dusty tans and off-whites, the slurry and drying racks
- Furnace Room: warm oranges and reds, the burnout furnace's glow spilling into the room
- Pour Room: the brightest room in the shop, molten metal orange and yellow against a darker background
- Post Processing: cooler grays and blues, grinding dust and finished metal

**Technicians:** small chibi-style sprites with simple 2 to 4 frame work loops, nothing elaborate. Skill tier should read at a glance, something like a plain uniform for an Apprentice building up to a distinct vest or hard hat color for a Master, so you can tell your best people apart on the floor without opening a menu.

**Stations:** each one gets its own clear silhouette so the floor reads well even zoomed out, the printer as a boxy machine with a visible print bed, the burnout furnace as a big glowing industrial box, the pour station built around a crucible and induction coil, and so on.

**UI chrome:** chunky pixel bordered panels and a pixel font, applied to the vertical stepper and any menus, keeping the retro feel consistent everywhere, not just on the shop floor itself.

**Defect alerts:** a flashing pixel icon or glowing outline on the affected part, the same visual language old RPGs use for an exclamation mark over a character's head, immediate and readable at a glance.

**Resin parts, once R&D unlocks them:** worth giving self binding resin patterns a distinct tint or shimmer so a resin part reads differently from a standard shelled part at a glance.

---

## 17. Starting Timer and Batch Numbers

These are first pass numbers, meant to be playtested and tuned, not locked in. They loosely follow real world proportions (shelling and burnout are your two longest real processes, so they stay your two longest timers) but compressed down to a mobile session length.

Each station has a Tier 1 (starting) value and a Tier 5 (fully upgraded) value, with four upgrade tiers in between splitting the difference. Time drops roughly by half at max tier, batch caps grow more aggressively since that is where the "shop getting bigger" feeling comes from.

| Station | Tier 1 Timer | Tier 1 Batch Cap | Tier 5 Timer | Tier 5 Batch Cap |
|---|---|---|---|---|
| Printing | 15 min | 1 (add printers to scale, see note) | 8 min | 1 per printer |
| Structured light scan | 2 min | 1 | 1 min | 5 |
| Deplate | 10 min | 4 | 5 min | 8 |
| UV cure | 12 min | 6 | 6 min | 10 |
| Pour cup attach | 3 min | 1 | 2 min | 5 |
| Shelling (per coat, 8 to 14 coats needed) | 20 min/coat, 8 coats required | 4 shells | 10 min/coat, 6 coats required | 12 shells |
| Burnout | 45 min | 8 | 25 min | 16 |
| Pour | 20 min | 3 molds | 12 min | 7 molds |
| Deshell | 5 min | 1 | 3 min | 5 |
| Abrasive blast | 12 min | 6 | 7 min | 14 |
| Ship | instant | unlimited | instant | unlimited |

A few notes on the reasoning:
- **Shelling's Tier 5 batch cap lands at 12**, which lines up with the real world WIP ceiling you have already documented on the shop floor. That is a nice bit of thematic payoff: fully upgrading shelling in game means matching what your real shelling tech can actually handle.
- **Shelling and burnout get the biggest raw time reductions** since those are your two real bottlenecks, so upgrading them should feel the most impactful.
- **Printing scales differently.** Rather than a batch cap, it probably makes more sense to unlock additional printers as an upgrade, since that mirrors having multiple machines in the Print Room rather than one machine doing bigger jobs.
- At Tier 1, one part moving through the whole pipeline solo takes roughly 4 to 5 hours. That is a reasonable idle game pace to start (long enough to encourage checking back later, short enough not to feel dead), and it should shrink noticeably as upgrades come in.
- Upgrade cost should scale up per tier, something like each tier costing roughly 1.5 to 2 times the previous one in currency. Worth considering gating Tier 4 and 5 behind a shipped parts milestone as well as currency, so late upgrades feel earned rather than just bought.

---

## 18. Current Implementation Status

A running account of what actually exists in the Godot project right now versus what's still just design on paper. Claude Code maintains a more granular, code-level version of this at the end of every session in the project's own `CLAUDE.md`, reproduced here at a design level so this one document stays the full picture without needing to cross-reference two files.

### Built

**Foundation** — Godot 4.7 project, Vulkan renderer (switched from D3D12 after it silently ate mouse input on one dev machine), a fixed 480x270 viewport with aspect-keep stretch, and a GameData autoload singleton holding all shared state.

**UI Theme** — a shared pixel art theme (Section 16) applied project-wide, reaching the Station Detail Menu, Menu overlay, Shop overlay, and the floor's own labels automatically rather than needing to be set per scene. A pixel font, sharp corners, chunky borders, and a palette pulled straight from the room palettes, warm tan panels, dark borders, the Pour Room's yellow-orange for hover and selected states, the Furnace Room's ember orange for pressed states, so interacting with a button reads as "heating up" rather than a generic color swap. A couple of real bugs surfaced and got fixed along the way: the pixel font initially rendered soft rather than crisp until its import settings were corrected, and the floor's own world-space text (unlike the HUD, which lives in screen space) needed extra work to stay legible and stop breaking into visual noise across the camera's full zoom range, down to seeing the entire floor at once.

**Stations** — one reusable, data-driven Station scene covers every station from Section 4's revised table (Section 21), configured via exported properties rather than one scene per station. Deplate is gone (collecting off a printer is the deplate action); Clean, Patching, and Mold Prep exist and sit in their revised Print Room / Furnace Room positions; the real pipeline sequence is Printing → Clean → UV Cure → Structured Light Scan → Patching → Pour Cup Attach → Shelling → Burnout → Mold Prep → Pour → Deshell → Abrasive Blast → Ship. Rack capacity and batch size are fully independent, purchasable stats per station now, not one derived from the other - upgrading a station's rack (any station) genuinely grows how many parts can wait there; upgrading its tier changes batch size only for the three stations Section 21 calls out (see below), everywhere else tier is still cosmetic only. Printing is no longer one shared station - the player purchases individual printer units, capped by factory level (Level 1 allows 2; nothing yet raises factory level past 1), each independently tiered, and per-printer tier eventually unlocks batching on that specific machine. Shelling runs a single combined timer at Tier 1 same as before, but Tier 2+ replaces that with a genuinely different model: several parts can run at once, each on its own independent clock, rather than one shared batch timer - the parallel-run cap grows with tier. Abrasive Blast is unbatched at Tier 1 and unlocks batching at Tier 2+, matching the revised table. Upgrading a station's tier still spends real currency and swaps art where it exists.

**Technicians and Parts, now genuinely physical, and now able to share a station** — the biggest system in the project, extended twice more this session on top of last session's physicality work. A technician is a real single-location entity with an actual position on the floor. Assigned to one station, they stay there; assigned to more than one, they walk between them, arrive, do exactly one real thing, then move on. **More than one technician can now be assigned to the same station at once** (previously assigning a second technician evicted the first). Only one of them is ever the *active worker* actually running that station's automation at a time - whoever physically arrives first while the slot is open claims it, and holds it until they actually leave. Anyone else assigned who's also physically present is a visitor: they can still drop a carried part into the station's queue rack, but don't compete to run the machine, and move on again immediately rather than lingering. This is deliberately paired with a routing rule so multiple technicians don't pointlessly converge on the same station: carrying a part bound for a station is always a valid, unconditional reason to head there regardless of anyone else; without cargo, a technician only treats a station as worth visiting if nobody's already working it *and* no other technician assigned there (cargo-carrying or not) is currently physically closer. In practice this reproduces exactly the behavior you'd want by hand - two technicians both carrying parts for the same station both go, only the first to arrive stays and works it, the second just drops off and leaves; if a closer technician is already heading there for real work, a farther technician with nothing to deliver correctly stays out of the way instead of racing them there. Printing being purchasable in units meant staffing needed to change too: a technician can now be assigned to "Printing" as one responsibility rather than checking each printer individually, and that assignment automatically covers any printer bought later without needing to be touched again. **Manual Collect** (the fallback for a Ready part sitting at a station) is available whenever that station isn't *currently* being actively worked, not only when nobody's assigned there at all - a technician assigned to several stations can legitimately spend a long stretch away from one of them, and the player needs a way to intervene rather than waiting indefinitely. **Production now has real backpressure**: a station that would otherwise conjure new work from nothing (a staffed entry station's auto-queue, or the player's own manual Queue action) refuses to when the very next station has no room left, or when too many defective parts are already sitting unaddressed shopwide - previously an entry station just kept producing regardless of whether anything downstream could use it, piling an unbounded backlog into the Awaiting Transfer holding inventory. Carrying cargo still takes priority over starting fresh local work, so a technician who's already picked something up reliably delivers it rather than getting stuck endlessly restocking wherever they picked it up. Parts are physically carried in a small capped carry inventory rather than teleporting, falling back to the Awaiting Transfer pool when the technician present can't personally carry them onward. Stations hold a real queue rack of several arrived-but-not-started parts, shown as a visual grid in the Station Detail Menu rather than a plain text list - tapping a slot shows full detail, and holding it down longer shows a per-station familiarity breakdown for that part's geometry (see Quality, Defects, and Geometry Familiarity below). A staffed station's rack won't self-start the next part until its active worker is physically there to load it. The switchable routing strategy (push parts through vs. maximize machines running) is fully wired up per technician, and the multi-station productivity penalty genuinely divides a station's effective timer, not just displayed.

Worth being direct about a gap this surfaced: **station placement itself is still hand-positioned per room, not on a real tile grid**, and a technician's walk is a straight line to a station's fixed position rather than pathfinding around other stations. The grid, per-station footprints, and access points described just above haven't been built yet, what exists now is real physical movement and pacing, not yet real spatial navigation around obstacles.

**Menu overlay, reorganized this session away from plain scrolling lists** — three tabs, all live, no pausing. Overview groups every station under a room-name subheader instead of one flat list, and now names which specific part is currently at each station. Awaiting Transfer groups held parts by their associated contract, with a defects-only filter and real columns (part number, familiarity, defect if any, a send-to-next-station action) instead of one run-on line per part, and surfaces flagged parts first within each group. Contracts uses the same real-column treatment. Both entry points for routing a held part work (this tab, and the receiving station's own detail menu). The Traveler Card work order view is still not built; current per-part detail otherwise lives in the Station Detail Menu and this Overview tab. Every overlay now closes on Escape as well as tapping outside it.

**Shop overlay** — a Technicians tab, a Specialists tab, and (new this session) a Printers tab for buying additional printer units up to the factory-level cap. Technicians: hire by skill tier, see your roster, and assign to stations - Printing now shows as a single checkbox covering every owned printer rather than one per instance, and more than one technician can check the same station's box (see the multi-technician model above). All four skill tiers behave genuinely differently once staffed, not just cosmetically. Specialists: a simpler one-time-hire-per-type list, no assignment needed since a specialist's effect is shopwide.

**Quality, Defects, and Geometry Familiarity** — effectively all of Section 9 and Section 21.6/21.7 now. Defects can only originate at four stations (Printing, Shelling, Burnout, Pour) - Deshell and Abrasive Blast are purely mechanical, and every pass-through station (Clean, UV Cure, Scan, Patching, Pour Cup Attach, Mold Prep) never rolls one either. A flagged part is never held back from the player by default; Push Through (now available at Shelling, Burnout, Mold Prep, and Pour, not just Pour) lets a part proceed with a known defect, raising the relevant station's familiarity more than a normal clean pass would, win or lose, and destroying the part outright on a failure. The one exception where the player *can* choose not to proceed is gated on very high, no-weak-spot familiarity with that geometry - a Scrap action that only ever appears once that bar is met, surfacing the single weakest-link station's familiarity as a percentage right in that same prompt. Familiarity itself is no longer one score: a geometry tracks four separate values (Shelling, Burnout, Mold Prep, Pour), shown as a quick-glance average star rating everywhere a part appears in a list, with a genuine press-and-hold on a part revealing the full per-station breakdown. Patching auto-resolves any still-flagged printer-sourced defect deterministically as every part passes through, no player decision, quality scaling with the assigned technician's skill through the same speed mechanism every station already has. Mortar Patch is now scoped specifically to the Mold Prep station rather than available from anywhere a flagged part is shown. The three fix paths (Mortar Patch, Redesign, hired Specialists) and the escalation/grace-period/contamination mechanics from Section 9 are otherwise unchanged. **The Reputation hit that accompanies an unresolved part reaching Ship is real now, not stubbed (this session)** - see Contracts below.

**Contracts, and Reputation/randomized generation built this session (Section 8)** — the six starting contracts from Section 10 still load with their same placeholder deadline/payout numbers, but they're no longer the whole pool. Shop-wide Reputation (0-100, starting at 0) moves on three events: a contract completing without ever having gone overdue, a contract's deadline lapsing (a one-time penalty, not per-frame), and an unresolved-defective part reaching Ship (Section 9's previously-stubbed escalation half). Per-company Relationship (0-5 stars) moves alongside Reputation on those same three events. New contracts are randomly generated (company name and geometry/alloy rolled from independent pools, per the doc's own instruction) whenever the active pool runs low, gated to whichever tier the current Reputation has unlocked, with a repeat-client roll (rising with average relationship) and a 5-star-relationship tier-bump chance per Section 8. Meridian Aerospace, and any generated Flagship contract, still ships once rather than recurring - that half of Section 8 isn't modeled yet. Shown on the HUD (a new Reputation line next to Currency) and in the Menu Overlay's Contracts tab (a shop-wide summary line plus a per-contract relationship column).

**Shop floor and camera** — the open, room based layout from Section 5 is built: all six rooms, every station hand-positioned and wired to the revised pipeline order, a freely pannable and zoomable camera clamped to the floor's edges. Zooming (mouse wheel or pinch) now anchors to the cursor/gesture position rather than always zooming toward the screen center. **Station/room label text is now rendered screen-space rather than as part of the zoomable world (this session)** - it stays crisp and legible at any zoom level instead of shrinking or getting hidden past a threshold, with an overlap-suppression pass deciding which labels show at once rather than a hard zoom cutoff. Rooms are currently plain colored zones, not real room art, and 8 of 12 stations still render as an identical generic placeholder box rather than a distinct silhouette - both still open, the latter explicitly deferred this session in favor of the text fix specifically.

**Art assets ready but not yet wired in** — the Print Room floor tileset is sliced into individual tiles with a real Godot TileSet resource built from it, just not yet swapped in for the current colored zone.

### Not yet built

- Real geometry and alloy data (Section 10), contracts currently carry flavor text strings only - the new per-station familiarity model, and the new randomized contract generation, both track/roll against the same flavor-text geometry names Section 10 would eventually replace
- Recurring flagship contracts (Section 8) - Meridian Aerospace, and any generated Flagship-tier contract, still ship once rather than repeating
- Alloy stock as a purchasable, depletable resource, and wage deduction, neither is hooked up to a real economy tick yet (Section 11)
- Real simultaneous batching for every station except Shelling's new Tier 2+ parallel timers - other stations still hold several parts in a queue rack but process them one at a time through a single active slot rather than running a batch together (Section 4/17)
- Station upgrade effects beyond sprite swap and the three station-specific batch-size cases (printer instances, Abrasive Blast, Shelling's parallel-run cap) - every other station's tier upgrade is still cosmetic only, and general per-tier speed/batch growth isn't implemented (Section 17)
- Factory level, which gates the printer purchase cap, never actually rises past 1 - nothing yet defines what's supposed to raise it
- Grid-based station placement, per-station footprints, and access points, technician movement is real and physical now, but it's a straight line to a station's fixed position, not pathfinding around obstacles on a real grid (Section 5) - this also means a parallel-shelling station that's only partially busy isn't always correctly prioritized by a technician deciding where to walk next among several assigned stations, a route-planning quality gap rather than a correctness one
- Distinct technician art per skill tier, all four currently render identically, and still a static sprite with no walk-cycle frames despite genuinely moving now
- The Floor Editor (Section 5)
- Mini games as a timer speed up (Section 2)
- The entire Research and Development system (Section 12)
- The Traveler Card work order view (Section 6)
- Shelling's real per-coat sub-loop, still one combined timer per run (whether that's the single Tier 1 timer or one of several parallel Tier 2+ runs) rather than 8 individual coat cycles (Section 17)
- Real room art (current floor uses colored zones) and distinct per-station placeholder art (8 of 12 stations still share one generic tinted box) - Section 16's "each station gets its own clear silhouette" is still unmet on the art side, even though label text readability at any zoom is now fixed (see Section 18's Shop floor and camera entry)
- The entire Settings Menu (Section 19), design only so far
- The Shop overlay's Hire/Roster/Specialist/Printer lists weren't part of this session's menu reorganization (Section 22.5) - only the Menu Overlay's three tabs and the Station Detail Menu's part-insert list got the new grouped/filtered/columnar treatment
- The entire tycoon-pivot retention layer (Section 23), design only so far: rotating live events / special commissions, rare event-only alloy collectibles, the collectible album meta-progression screen, the rolling 3-of-7-day login reward, and the daily quest system. The Idle Plus Active Hybrid and Contract/Reputation-progression pieces of that same pivot (Section 23.1, 23.4) are design principles already reflected in existing systems rather than new features to build, see those subsections for what's already covered

---

## 19. Settings Menu

Not part of the core production loop, but every idle game needs a place to configure the experience around it rather than just the shop floor itself. Likely its own button/overlay alongside Menu and Shop (Section 6), following the same live-panel pattern - or a tab bolted onto one of those two - rather than a separate paused screen; exact placement is an implementation detail to settle later, this section is about what belongs in it.

**Audio:**
- Master, Music, and SFX volume sliders, each independently mutable - a station's own working noise (the printer's motor, the furnace's roar, the pour room's hiss) should read as SFX, any looping background score as Music, so a player can kill the music and keep the shop's ambience, or vice versa
- A separate mute toggle for UI sounds (button taps, defect alerts per Section 15) if those end up on their own bus

**Display:**
- **Station title visibility** - a toggle for whether station Name/Status labels render on the floor at all. Directly useful at the zoomed-way-out overview level (Section 5's camera can zoom out far enough to see the whole floor at once), where per-station text competing for a small amount of screen space is inherently a losing battle no matter how it's scaled - a player who mostly wants the floor-level silhouette read (Section 16: "each [station] gets its own clear silhouette so the floor reads well even zoomed out") and prefers to check status via the Menu Overlay's Overview tab or a station's own detail popup should be able to turn the labels off entirely rather than fight with small text
- A text size option (small/medium/large, or a straight scale multiplier) for the pixel font, for players who want bigger UI text than the default without changing anything else
- Reduce Motion - dampens or disables the technician walk animation and any future mini game motion for players sensitive to a lot of small on-screen movement, without losing any of the underlying simulation (a technician's actual travel time doesn't change, only whether it's rendered as a smooth walk or a snap)

**Idle-game housekeeping:**
- An offline progress summary toggle - whether returning to the app after time away shows a "here's what happened while you were gone" recap (Section 2's core promise) or just drops the player straight back onto the live floor
- Notification permission/toggle for mobile push alerts (a contract deadline approaching, a defect grace period about to lapse per Section 9, a station finishing a long timer like Shelling or Burnout) - useful for an idle game specifically because the point is not having the app open all the time
- Haptics toggle for mobile tap feedback

**Data:**
- Reset save / start over, with a real confirmation step given how much stands to be lost (contracts, reputation, hired roster, R&D progress)

**Not itself a settings item, but worth deciding here:** whether any of this needs to be resolution/device-independent given the fixed 480x270 base viewport (Section 1's `project.godot` setup) - text size and station title visibility both interact with that base resolution choice directly.

---

## 20. Suggested Next Steps

Refreshed against what's actually built so far, in roughly the order they'd come up:

1. ~~Implement the revised station/pipeline model from Section 21~~ - **done.** Deplate removed, Clean/Patching/Mold Prep added, rack capacity and batch size split into independent tracks, Shelling's Tier 2+ parallel timers, purchasable/capped printer units, and per-station familiarity are all built - see Built above and Section 21/22.
2. ~~Quality, Defects, and Geometry Familiarity (Section 9)~~ - **done, including Reputation.** The narrowed four defect sources, generalized Push Through, the very-high-familiarity Scrap exception from Section 21.6/21.7, and (this session) the Ship-time Reputation consequence that was previously stubbed are all built.
3. ~~Build real Reputation and randomized contract generation with repeat clients (Section 8)~~ - **done this session.** Shop-wide Reputation, per-company Relationship, Reputation-gated tier rolling, repeat clients, and a low-pool generation trigger all replace the old fixed-six-contract-only setup - see Built above. Not built as part of this: recurring Flagship contracts, and the real geometry/alloy system (item 7 below) that would eventually replace the flavor-text pools this rolls from.
4. Build the economy properly, wage deduction and alloy stock, replacing the placeholder currency number with the real system from Section 11
5. Decide what actually raises factory level (Section 21.2 introduced the gate on printer count but never specified what advances it past 1) - small, but blocks a real printer-scaling progression
6. Build the Traveler Card work order view (Section 6), the two-stage onboarding sequence in Section 1 depends on it existing
7. Replace flavor-text geometry and alloy with the real system from Section 10, including familiarity carryover between related families - the per-station familiarity model from Section 21.7, and the new randomized contract generation (item 3 above), both already assume this will eventually replace the flavor-text names they currently key off of/roll from
8. Whenever it's convenient rather than blocking: build the actual grid, station footprints, and access points from Section 5, and give technicians real pathfinding around them instead of a straight line to a fixed position - this would also let the closest-claimant routing coordination from Section 22.1 reason about real walking distance instead of straight-line distance
9. ~~Zoomed-out label readability (text half)~~ - **done, a later session**: station/room labels now render screen-space, always crisp regardless of zoom, with overlap suppression instead of a hard hide threshold. Real room art and distinct per-station placeholder art (Section 16) are still open - the art half of "zoomed-out floor readability" remains deliberately deferred
10. Layer in the tycoon-pivot retention systems (Section 23), now that real Reputation and randomized contract generation exist (item 3, done this session): the rolling 3-of-7-day login streak and daily quest system (Section 23.3) have the fewest remaining dependencies and can go first, then rotating live events and the collectible album (Section 23.2), which still want real geometry families (item 7 above) to have full-fledged content to rotate through rather than flavor-text pools
11. Once the core loop is fully real, layer in Research and Development (Section 12), the Floor Editor, technician art per tier and walk-cycle frames, mini games, then the Settings Menu (Section 19)

---

## 21. Session Changes: Pipeline, Batching, and Defect Rework (Implementation Notes)

*Added this session. This section exists specifically so Claude Code does not have to reconstruct intent from diffs scattered across Sections 3, 4, 5, and 9 above. It restates every change made this session in one place, with the reasoning, so implementation decisions can be made consistently. Where this section and an earlier one disagree, this section is the current source of truth; the earlier section's prose has already been updated to match, but its surrounding context may still describe the old system.*

### 21.1 Rack capacity and batch size are now two independent numbers

Previously, rack capacity was a flat derived value tied to `batch_cap` (`Station._rack_capacity()` was `batch_cap - 1`, floored at 1). That coupling is gone.

- **Rack capacity**: how many parts can physically sit at a station waiting (in the rack, not the active slot). Every station starts with exactly one rack slot at Tier 1, conceptually a small desk or holding spot next to the machine, not a real rack yet. Upgrading rack capacity is its own purchase, separate from tier, and is what turns that desk into an actual multi-slot rack over time.
- **Batch size**: how many parts run together sharing a single timer. This is what tier upgrades affect, and the effect is station-specific (see 21.3).
- A station can have a rack capacity larger than its current batch size. Parts beyond the batch size just wait their turn in the rack for the next run.
- Implementation implication: `Station` needs two independent upgradeable stats where there is currently one derived one. Whatever replaces `_rack_capacity()` should not reference `batch_cap`/`batch_size` at all going forward.

### 21.2 Printing: multiple purchasable units, capped by factory level

- The player purchases individual printers rather than upgrading one shared Printing station.
- Each printer starts at Tier 1 (unbatched, one part at a time) independently of any other printer's tier.
- Tier upgrades on a given printer eventually unlock batched print jobs on that printer (more than one part printing per run on that specific machine).
- The number of printers a player is allowed to own is capped by factory level (example given: a Level 1 factory allows 2 printers). This cap is a new progression gate that does not exist anywhere else in the current systems and will need its own data (factory level → printer cap table).
- Implementation implication: Printing can no longer be a single `Station` node/instance the way it is today. It needs to become a collection of independently-tiered station instances, spawnable up to a cap, likely still using the same reusable Station scene per Section 18's data-driven approach, just multiple instances of it.

### 21.3 Deplate is removed as a station

- Deplate no longer exists anywhere in the pipeline, floor layout, or Station Mechanics table.
- Collecting a finished pattern off a printer **is** the deplate action. No separate timer, no separate station, no separate player action.
- Rationale given: a whole dedicated station for an action that's really just "picking up the part" didn't make sense. It may return later as a real distinct station once the R&D self-binding-resin printed-mold system is built out, but not before.
- Implementation implication: remove `Deplate` from `GameData.PIPELINE_ORDER` and any station definitions. The Print Room's station list shrinks by one, and the immediate next step after collecting from a printer is now Clean.

### 21.4 New stations: Clean, Patching, Mold Prep

**Clean** (Print Room, right after collecting from the printer, before UV Cure)
- Removes excess resin.
- Batched.
- No defect risk of its own.

**Patching** (Print Room, after Structured Light Scan, before Shelling/Pour Cup Attach)
- Every part passes through here, not just flagged ones.
- Not batched.
- Auto-resolves any printer-sourced defect (warping, dimensional non-compliance, holes) without a player decision. Outcome quality scales with the skill of the technician assigned to the station, the same skill tiers used elsewhere (Apprentice/Technician/Senior Technician/Master).
- For an unflagged part, Patching is still a real pass: it smooths surfaces and closes small holes on every part as a matter of course before Shelling.
- This is also where the "no decline option" design decision lives mechanically: because Patching always runs and always auto-resolves, there is never a point in the Print Room phase where the player is asked whether to proceed with a defective part. See 21.6.

**Mold Prep** (Furnace Room, after Burnout, before Pour)
- Every part passes through here, not just flagged ones.
- Not batched.
- This is where Mortar Patch happens. Mortar Patch is specifically for shell cracks, whether the crack originated at Shelling or surfaced/worsened during Burnout. It is a patch, not a fix (does not raise Shelling or Burnout familiarity, per the existing Section 9 rule, unchanged).
- Also the natural place to model insulation decisions ahead of Pour (raises Mold Prep familiarity when pushed through on a part without established insulation needs, see 21.6).

### 21.5 Revised Print Room order

Old order: Print → Structured Light Scan → Deplate → UV Cure

**New order: Print → Clean → UV Cure → Structured Light Scan → Patching → (Pour Cup Attach →) Shelling**

Reasoning given for this exact order: resin residue could plausibly throw off the structured light scan's reading, so Cleaning and UV Cure both need to happen before Scan, not after it. Patching comes after Scan since Patching is what actually resolves whatever Scan flags, and it needs to happen before Shelling since every part needs smoothed surfaces and no holes going into shell building.

### 21.6 Defects: sources narrowed to four stations, no decline option, Push Through generalized

**Defect sources are now exactly four:** Printing, Shelling, Burnout, Pour. Deshell and Abrasive Blast carry no defect risk at all going forward, they are purely mechanical steps. (Structured Light Scan, Clean, UV Cure, Patching, Mold Prep, Pour Cup Attach do not themselves roll for defects; Scan's job is purely detection of what Printing already caused.)

**No player decline option, ever, with exactly one exception:**
- A flagged part is never held back or scrapped by default, not for dimensional non-compliance, not for holes, not for any defect category, regardless of the player's familiarity with that geometry.
- Real-world framing given for this: you don't scrap a first-article part just for being imperfect, the whole point of a trial is learning what breaks and why.
- **The one exception:** if the player already has very high familiarity with a specific geometry and can predict with confidence that a given part will not meet a customer's tolerance, they can choose not to proceed. This requires established expertise to access, it is not available on a novel or lightly-familiar geometry. This is the only scrap-before-ship decision point in the whole game.
- Printing-sourced defects specifically never reach a player decision point at all, they flow straight through Scan into Patching's auto-resolve, per 21.4.

**Push Through is generalized beyond Pour.** Previously Push Through was a Pour-only mechanic. It now applies conceptually to any part moving through the pipeline with a known defect, and raises familiarity at whichever downstream station(s) are relevant to what that defect teaches:
- Pushing through a Shelling-sourced issue raises **Shelling parameters** familiarity.
- Pushing through a Burnout-sourced issue raises **Burnout parameters** familiarity, and may inform a real redesign choice (vent holes, changing the part's orientation off the printer).
- Passing through Mold Prep with an unresolved insulation question raises **Mold Prep parameters** familiarity.
- Pushing through at Pour raises **Pour parameters** familiarity, and can involve a real resource choice, pouring in revert metal saved from previous trial pours instead of fresh alloy, as well as pour temperature.
- In every case: normal defect odds still apply at that station, but a push-through always grants a bigger familiarity jump than a normal clean pass would, win or lose, same rule as the original Pour-only version.
- An unfixable Burnout defect still destroys the part as a shippable unit; it's kept only as a familiarity trial, same as before, this case is unchanged by the generalization.

### 21.7 Familiarity becomes per-station, not a single score

- A part's geometry now tracks **four separate familiarity values**: Shelling, Burnout, Mold Prep, Pour. (Printing familiarity is not tracked the same way, since printer defects are always auto-resolved at Patching rather than being a risk the player manages directly.)
- Redesign fixes, resolved specialist visits, and Push Through attempts each raise the specific station's familiarity they're associated with, not a single shared number.
- **Display, two levels:**
  - **Quick glance** (any part shown in a menu/list): a single **average** of the four per-station values, shown as a star rating, same visual language as the old single score.
  - **Detail view** (press-and-hold on the part): all four per-station familiarity values shown individually.
  - **When prompted about proceeding with a defective part specifically**, also surface the single **weakest-link** station's familiarity as a **percentage** alongside the average star rating, since the weakest station is what actually matters for judging that specific decision, an average could otherwise hide a real problem area.
- Section 10's geometry family carryover (the ~50% partial familiarity transfer between related families, e.g. Pump Housing to Gear Housing) should now be understood as applying per-station, not as one blended number, though the ~50% figure itself is unchanged.

### 21.8 Suggested implementation order for this session's changes

Given the scope, a reasonable build order (not mandated, just a sensible dependency chain):
1. Data model first: split `Station`'s rack capacity from batch size; add per-station familiarity (4 values) to whatever currently holds a single familiarity score per geometry.
2. Remove Deplate from `PIPELINE_ORDER` and station definitions; add Clean, Patching, Mold Prep in the correct pipeline positions.
3. Rework Printing into multiple independently-tiered purchasable instances with a factory-level cap.
4. Shelling's Tier 2+ parallel-independent-timer behavior (this is a genuinely different runtime model than shared-batch, worth its own design pass on the Station scene before writing code).
5. Wire Patching's auto-resolve-scaled-by-technician-skill logic and Mold Prep's Mortar Patch flow.
6. Update defect roll logic to only fire at the four sources, and remove any decline-to-proceed prompt except the single very-familiar exception.
7. Wire the two-tier familiarity display (average star at a glance, per-station detail on hold, weakest-link percent in the proceed-with-defect prompt).

---

## 22. Session Changes: Multi-Technician Coordination, Backpressure, and UI Reorganization (Implementation Notes)

*Added this session, in the same spirit as Section 21: this restates every design decision made this session in one place, with the reasoning, most of them arising directly from playtesting Section 21's own implementation rather than from the original spec. Where this section disagrees with earlier prose (particularly Section 7's technician model, which implicitly assumed one technician per station throughout), this section is the current source of truth.*

### 22.1 Multiple technicians can now be assigned to one station

Section 7 never explicitly said a station could only have one technician, but every mechanic assumed it. That's no longer true - a station can have several technicians assigned, but only one of them is ever the **active worker** actually running its automation at a time, and the coordination rules below keep multiple technicians from pointlessly converging on the same place.

- **Claiming:** the first assigned technician to physically arrive at a station while nobody else is already working it becomes the active worker there, whether or not they immediately find anything to do. They hold that role until they actually leave for somewhere else, at which point it's released for whoever's still there (or arrives next) to claim.
- **Visitors:** any other assigned technician who's also physically present - most commonly because they're carrying cargo bound for that exact station - can still drop that cargo into the queue rack, but doesn't compete to run the machine, and doesn't linger afterward: if there's nothing left to deposit, they immediately move on to wherever's actually worth their time next.
- **Avoiding redundant walking:** a technician carrying a part bound for a station always has an unconditional reason to head there, regardless of who else is doing what. Without cargo, a station is only worth walking to for "real work" reasons (an idle station with loadable work, or a finished part ready to carry onward, per the existing routing-strategy logic) if nobody's already working it, and no other technician assigned there - cargo-carrying or not - is currently physically closer. This single rule, applied from each technician's own perspective independently, reproduces the intuitive behavior in every case: two technicians both carrying parts for the same station both go, and only the first to arrive stays to work it; if a closer technician is already converging on a station for a real reason, a farther technician with nothing to deliver correctly leaves it alone instead of racing them there.

This is a real behavioral evolution of Section 7's "Multi-station assignment and the walking penalty" - the productivity penalty for spreading one technician across several stations is unchanged, this section is specifically about what happens when several *different* technicians are assigned to the *same* station.

### 22.2 Printing is staffed as one responsibility, not per printer unit

Section 21.2 made Printing a collection of independently-purchasable, independently-tiered printer units. Staffing follows the same logic: the player assigns a technician to "Printing" as a single responsibility rather than checking each printer individually, and that assignment automatically covers any printer bought later without needing to be touched again - buying a third printer doesn't require re-visiting every technician's assignments to add it. A technician covering the Printing responsibility still only ever actively works one physical printer at a time, same as covering any other multiple assigned stations - the group assignment is a staffing/UI convenience, not a change to the one-active-worker-at-a-time rule from 22.1.

### 22.3 Production backpressure

Previously, a staffed entry station (or the player's own manual queue action) would create a new part the instant its own slot was free, with no regard for whether anything downstream could actually use it. Since the Awaiting Transfer holding inventory has no cap, a clogged pipeline just meant an ever-growing, unbounded pile of parts nobody could route anywhere - reported directly as not wanting technicians "just pumping out parts continuously."

Production of a *new* part (the only two places this ever happens: a staffed entry station's auto-queue, and the player's own manual Queue action - never receiving a part from an upstream station, which is already naturally capacity-gated) now pauses under two conditions:
- The very next station has no room at all - its rack and active slot are both full.
- Too many defective parts are already sitting unaddressed shopwide - "too many unanswered prompts for what the user wants to do about defective parts," a shopwide count rather than per-contract or per-station.

Either condition clears automatically once the backlog is dealt with; there's no separate unpause action needed. The exact thresholds (how full is "full," how many unaddressed defects is "too many") are first-pass placeholders, same spirit as every other invented number in this project - worth tuning once playtested rather than treated as final balance.

### 22.4 Manual Collect no longer requires a station to be fully unstaffed

Previously, the Collect fallback (freeing a Ready part manually into Awaiting Transfer) was hidden the instant *any* technician was assigned to a station, even if that technician was legitimately away working a different one of their assigned stations and might not cycle back for a while. Combined with 22.1's coordination rules meaning a technician can now correctly stay put at a more useful station for a genuinely long stretch rather than needlessly wandering, this could leave a Ready part stuck with no way for the player to intervene. Collect is now available whenever a station isn't *currently* being actively worked, regardless of whether anyone's assigned there at all.

### 22.5 Menus reorganized around categories, filters, and real columns instead of plain scrolling lists

Every list-of-parts or list-of-stations menu was originally one long vertically-scrolling list of run-on text lines. Reorganized this session, starting with the two views most directly showing a list of parts and the floor's own overview:

- **Awaiting Transfer** groups held parts under a subheader per associated contract, offers a "defects only" filter, and lays each part out in real columns (part number, familiarity, defect if flagged, a send-to-next-station action) instead of one concatenated string - defective parts sort first within each group so anything needing attention isn't buried.
- **A station's own part-insert list** (the "next station's own Batch Picker" entry point from Section 6) got the same column treatment.
- **The Overview tab** groups every station under a room-name subheader - a natural, already-existing category for a list of stations specifically - rather than one flat list, and now also names which specific part is currently at each station.
- **Contracts** uses the same real-column layout.

"Type of part" was also requested as a possible category, but there's no real part-type system to filter by yet beyond a contract's flavor-text geometry/alloy strings (Section 10) - contract grouping is the closest existing equivalent until that's built. The Shop overlay's Hire/Roster/Specialist/Printer lists weren't part of this reorganization pass - they don't have the same "wall of text" problem each row already being a small number of clearly separated fields - but haven't been deliberately redesigned to match either, a reasonable next target if they turn out to need it too.

### 22.6 Camera and input polish

- Zooming (mouse wheel scroll, or a pinch gesture) now anchors to the cursor/gesture position rather than always zooming toward the screen center - standard behavior for any zoomable map or canvas, previously missing.
- Escape now closes whichever menu overlay is currently open, in addition to the existing tap-outside-to-close behavior.

---

## 23. Tycoon Pivot: Retention and Engagement Systems

*Added this session, folding in a separate round of design notes ("Foundry - Tycoon Pivot Design Notes") written to push the project further toward a tycoon-style game - more collection, more reasons to come back on a schedule, a clearer contract-driven power curve - on top of the hybrid idle/factory-management foundation that was already there. Two of that document's four systems turned out to already be exactly what this doc's existing sections describe, so those two are handled as cross-references and light additions to Sections 2, 8, and 14 rather than duplicated here (see 23.1 and 23.4 below). The two genuinely new systems, Live Events/Collections and the Rolling Streak/Daily Quest system, get full design treatment in 23.2 and 23.3. As with Sections 21 and 22, this section exists so the reasoning lives in one place rather than scattered across diffs, and where anything here disagrees with older prose, this section wins.*

### 23.1 Idle Plus Active Hybrid - already the core loop, see Section 2

The tycoon pivot notes describe an "idle plus active hybrid," foreground production while the player is present, background production while they're away, with the game deliberately steering the best profits toward active sessions (citing Idle Miner Tycoon as the genre benchmark). This is not a new system, it's a restatement of Section 2's Core Loop, which already splits the game into a background idle layer (timers run whether or not the app is open) and a foreground active layer (queuing, batch choices, and routing are the real decisions). Section 2 has been updated with a short paragraph naming this explicitly as a design guardrail to protect going forward: active play should reliably out-earn the same stretch of idle time, and that gap should come from systems that already exist (Push Through's bigger familiarity payoff, the multi-station walking penalty, grace-period defect handling) rather than a bolted-on idle tax. Nothing here requires new code; it's a lens to hold every future system against.

### 23.2 Collection and Live Events

Two new systems, tied together because they share one mechanism: content that only exists for a limited window, and a permanent record of what a player has caught.

**Live Events - rotating special commissions:**
- On a rotating schedule (weekly is a reasonable first-pass cadence, same "first pass, needs playtesting" caveat as every other number in this doc), the contract pool offered to the player includes one or more **event contracts** alongside the normal Tier 1-4 rotation from Section 8.
- Mechanically, an event contract is a normal `Contract` (Section 8's structure: customer, geometry, quantity, deadline, payout) with an `is_event` flag and its own event window separate from its own per-contract deadline - the event window governs whether the contract is *offered* at all, the deadline still governs how long the player has to finish it once accepted.
- Event contracts skew toward unusual geometries (an off-family shape not in the player's normal rotation) or unusual alloys, and pay a premium over what a same-tier standard contract would, both to justify chasing them and to make missing one sting a little.
- Because they're time-boxed on the offer side, event contracts are the natural place to let a player spend saved-up currency or resources to skip ahead if they're at risk of missing the window - the same "spend effort/resource instead of time" principle Section 2's optional mini game layer already establishes, applied to an event's clock instead of a station's.

**Rare alloy collectibles:**
- Some alloys (Section 10/11's alloy table) are **event-exclusive** - only purchasable, or only usable to fulfill a contract, during a live event window. A rare alloy showing up standardizes what "worth logging in for" means beyond just the contract's payout number.
- These sit in the same Section 11 alloy-stock system as standard alloys (purchased in batches, consumed by Pour, can run out mid-run), just with a time-limited storefront window rather than being always available.

**Collectible album, the meta-progression layer:**
- A persistent, permanent gallery screen (separate from the Menu/Shop overlays, its own entry point) recording every distinct geometry the shop has ever produced, one "card" per geometry (or per geometry x alloy combination, a first-pass call that should be revisited once Section 10's real geometry system exists - geometry alone may turn out to be the more legible collection axis).
- **This reuses Geometry Familiarity almost entirely rather than inventing a new tracked value.** A card's own state already has a natural source: 0 stars is an empty/silhouette card (a geometry the shop has heard of but never shipped), first successful ship reveals the card, and reaching 5-star average familiarity (Section 9/21.7) is what earns the card's "mastered" foil/frame treatment - no separate `is_collected` flag needed, the existing familiarity data already answers "has this been collected, and how thoroughly."
- Event-exclusive geometries or alloys (see above) grant a distinctly bordered, rarer card variant obtainable only by completing that specific event contract during its live window - once the window closes, that specific card variant is gone until the event rotates back around, which is what gives the album real FOMO-driven pull to check in regularly rather than just being a trophy case.
- The album is read-only progression, it doesn't grant gameplay bonuses on its own beyond what Geometry Familiarity already grants (Section 9's defect-risk reduction) - its job is retention and completionist pull, not another power-up layer stacked on top of an already-established one.

### 23.3 Rolling Streak and Daily Quest System

**Rolling login reward, replacing a strict daily streak:**
- Track a rolling 7-day window of which days the player opened the app, not a counter that resets to zero on a missed day. Hitting a cumulative threshold of days logged in *within that trailing week* (a first-pass table: 3/7 days for a small reward, 5/7 for a medium one, 7/7 for the best one) unlocks that tier's reward, and the window keeps rolling forward day by day rather than punishing one missed day by erasing everything built up before it.
- Rationale carried directly from the source notes: a strict reset-on-miss streak measurably drives players away the day after they break it, since the accumulated investment is gone and restarting feels worse than not having played at all; a rolling window keeps the same "come back regularly" pull without that specific failure mode.
- Rewards at each threshold should lean toward things that reinforce the core loop rather than pure currency: a free instant-finish on one in-progress timer, a small bundle of a mid-tier alloy, a temporary defect-risk reduction for the day, that kind of thing - exact reward table is a balancing pass for later, not something this design note needs to lock down.

**Daily quests:**
- A short, refreshing-daily list of session-scoped objectives that point back at systems already in the game rather than introducing new busywork: ship N parts, resolve a flagged defect through any of the three fix paths (Section 9), successfully Push Through once, assign or reassign a technician, accept a new contract. Three to five active quests at a time is a reasonable first-pass count.
- Quests reward currency, reputation (once built, Section 8), or progress toward the rolling login threshold above - tying the systems together rather than running three completely separate reward economies in parallel.
- Distinct from Live Events (23.2) in scope and cadence: a daily quest is short, always achievable within a single session, and refreshes every day regardless of the event rotation; an event contract is a bigger, deadline-bound commitment that comes and goes on its own weekly-ish schedule.

### 23.4 Contract and Reputation-Based Progression - already Section 8, pacing formalized in Section 14

The tycoon pivot notes' fourth system, bigger jobs for bigger clients gated by reputation, with pacing stretching from short early sessions to longer late-game ones, is already Section 8's contract tier table and Section 7's technician-driven automation curve. Nothing structurally new is needed here. What this pass added: Section 14 (Session Feel) now states the target session-length numbers explicitly (roughly 5 to 15 minutes early game, 20 to 40 minutes late game) rather than leaving the pacing shift implicit in the contract tier table, and Section 8 now cross-references that target directly, so future contract-tier tuning (deadline lengths, quantities) has a concrete number to check itself against instead of just a qualitative "generous" versus "tight, long running" description.

### 23.5 Suggested implementation order

Consistent with Section 20's overall roadmap, but stated here with the dependency reasoning specific to these four systems:

1. **Rolling login streak and daily quests (23.3) first.** Neither depends on anything not already built - login tracking is a pure new save-data concern, and every quest objective listed above already exists as a real, working action in the game today. Lowest engineering risk, and the fastest of the four to actually start affecting retention.
2. **Live Events and the collectible album (23.2) after Reputation and real contract generation exist** (Section 20 item 3) - an event contract is still just a `Contract` with an offer window, so it wants a real contract-generation pipeline to plug into rather than being hand-authored on top of the current fixed six starting contracts. The album's "mastered" card state already rides on Geometry Familiarity, so it has no new blocking dependency of its own beyond that same contract-generation work feeding it real geometries to collect.
3. **23.1 and 23.4 need no dedicated implementation work** - they're standing design guardrails against Sections 2, 8, and 14, worth re-checking whenever a new system is designed, not a line item with its own build task.

---

## 24. Session Design Notes (2026-08-26): Contract Depth, Geometry Variety, and Staffing Skill

*Captured verbatim-in-spirit from a design conversation. Originally deferred per direct instruction ("don't make any changes to the game right now, let's just document these ideas") - 24.1, most of 24.9, and part of 24.3 were then actually built in a follow-up session (2026-08-26, same day) once a UI mockup made the shape concrete; each subsection below is marked BUILT or still an idea. Same purpose as Sections 21-23: get the reasoning and scope down in one place, so a future session isn't reconstructing intent from scratch. These are real extensions of Sections 8, 9, and 10 - where this section adds detail or changes a number, it should be read as an amendment to those sections, not a contradiction.*

### 24.1 Contracts as multiple line items, not one geometry each - BUILT

Every `Contract` today carries exactly one `geometry_name`. The idea: a single customer contract should be able to ask for **several different geometries at once**, each with its own quantity - "Acme Turbines needs 20 turbine blades AND 15 bracket assemblies AND 8 seal rings, all under one contract, one deadline, one payout." This is a data model change (`Contract` needs an array of line items - geometry + alloy + quantity + shipped-so-far, each tracked independently - rather than the current flat `quantity_required`/`quantity_shipped` pair), not just a display change: a Part still belongs to one line item's geometry, but "is this contract done" now means every line item individually reaching its required quantity, and the Contracts UI needs to show progress per line item, not just one bar for the whole contract.

**Built as described**, plus the follow-through this note flagged as necessary: `Contract.line_items: Array[Contract.LineItem]` (each its own geometry/alloy/quantity/shipped), `Part.line_item_index` so a Part always knows which specific line item it's fulfilling, `Station._try_create_part()` picks whichever line item still needs Parts (shipped-or-in-flight, not just shipped) rather than always the first, and `GameData.credit_contract_shipment()` now takes the Part so it credits the right line item. `Contract.is_complete`/`quantity_required`/`quantity_shipped` stay as aggregate getters across every line item, for anywhere a single combined progress bar still makes sense. One alloy per whole contract (not per line item), matching a real customer order being one material spec.

### 24.2 Reward contracts for finishing well AND fast, not just on time

Today, Reputation only moves on three binary events (on-time completion, a missed deadline, an unresolved defective part reaching Ship - see Section 8/Section 9's existing Reputation hooks). The idea: layer in a genuine **performance bonus** - completing a contract with zero (or very few) defective parts shipped, and/or finishing well ahead of the deadline, should earn extra currency and/or extra Reputation/Relationship on top of the base payout, not just avoid a penalty. This turns "how well and how fast you ran the contract" into a continuous score worth optimizing, not just a pass/fail gate. Needs its own numbers (how is "quality" measured across a whole contract with several line items now, per 24.1 - percent of parts shipped without ever having been flagged? What counts as "fast enough" to earn a speed bonus - a fraction of the original deadline?) before it can be built.

### 24.3 A much larger, visually distinct real geometry roster - PARTIALLY BUILT

Section 10 already sketches geometry families (Bracket, Valve, Housing, Impeller, Manifold, Turbine, Strut, Seal) with example parts and a complexity rating, but none of it has real in-game visuals yet - it's still flavor text. The idea, restated with concrete direction: build out a genuinely large pool of real aerospace-flavored geometries the player can *see* - turbine blades and vanes, blisks, recuperators, hot section components, and "anything under the sun" that a real aerospace foundry would actually cast - specifically so the game doesn't start feeling like the same handful of parts on repeat once a player's put in real hours. This is squarely Section 10's job finally getting real art/models rather than a new system, but the ask here is explicitly about the pool being *large* and *visually distinguishable*, not just mechanically distinct.

**Pool expanded, real visuals still not built.** `GameData.GEOMETRY_POOL`'s Turbine family gained Blisks, Nozzle Guide Vanes, and Compressor Vanes alongside the existing Turbine Blades/Vanes; a new HotSection family added Combustor Liners, Recuperators, and Hot Section Casings. Both families' minimum tier dropped from Flagship-only down to Industrial Accounts, so they show up meaningfully more often instead of gating almost the whole aerospace-signature roster behind the rarest tier. Still flavor text, though - each geometry gets only a small placeholder icon (a tinted bordered box + 2-3 letter abbreviation, family-colored) on the new Contract Offers screen (see 24.9), not real per-geometry art/silhouettes. That's still the open follow-up this subsection originally asked for.

### 24.4 Cored geometries - a new, harder category

A **cored** part (the casting term - a ceramic core placed inside the mold before pouring, dissolved or broken out afterward to leave internal passages, most commonly used for a turbine blade's internal cooling channels) is a genuinely different, harder geometry category from anything in Section 10's current family list, all of which are solid parts. This would need its own complexity tier (likely at or above Turbine's "Very High"/15-fixes-to-master per Section 10's table) and possibly its own process step or risk (a core that shifts or breaks during pour is a real-world failure mode a cored-parts mechanic could model, similar in spirit to how Shelling/Burnout/Pour already each have their own defect categories per Section 9). Flagged as a "later" addition, not part of the initial geometry-roster expansion in 24.3.

### 24.5 Familiarity carryover should vary per specific geometry pair, not a flat family-wide 50%

Section 10 already has a family-level carryover rule ("mastering a Pump Housing gives a real head start, something like 2 to 3 stars worth, on a later Gear Housing contract... roughly 50%"). The refinement: carryover shouldn't be one flat percentage for an entire family - two geometries can look almost identical (the example given: an A-vane and a C-vane, visually very similar) and deserve a high carryover, while two geometries in the same nominal family but shaped quite differently deserve less. This implies carryover becomes a **per-geometry-pair** value (or at least a finer-grained similarity score) rather than one number per family - a real data-modeling question (a lookup table keyed by geometry-pair? A computed similarity from shared traits like the family plus a shape-complexity delta?) worth a dedicated design pass rather than guessing at numbers now.

### 24.6 Defect risk never hits zero, confirmed as intentional

Restated for clarity, not a new rule: even at maximum familiarity (5 stars) and with a fully skilled technician staffing the station, there should still be a real, non-zero chance of a defect - this is already exactly what Section 9's familiarity/technician multiplier tables do (5-star familiarity floors at 10% of base risk, never lower; the best technician tier is 55%, never zero). Worth keeping explicit here since it came up directly in conversation - any future rework of the defect-risk formula should preserve this floor, not accidentally let a fully-mastered, fully-staffed station become 100% safe.

### 24.7 Specialists/engineers should have skill tiers too, same shape as Technicians

Today, a Specialist (Section 9's third fix path - Shell/Pour/Pattern) is a single flat one-time hire per type, no tiers. The idea: give Specialists (referred to here as "engineers") the same kind of skill-tier ladder Technicians already have (Section 7's Apprentice/Technician/Senior Technician/Master, increasing hire cost for a lower defect rate) - a more skilled engineer should both **resolve an existing defect more reliably** (when redesigning/reworking a flagged part) and, per the redesign's own downstream effect, make the geometry genuinely **easier for technicians to process afterward** (faster, and/or lower base risk) rather than every engineer producing an identical fix regardless of skill. This is a real expansion of `GameData.SpecialistType`/the hire-cost table, not a small tweak - `hire_specialist()`, the specialist-suppression math in `Station._roll_defect_outcome()`, and the Staff overlay's Specialists tab would all need a tier dimension added.

### 24.8 A difficulty rating per specific geometry, not just per family

Section 10's "Complexity" column (Low/Medium/High/Very High, mapped to "fixes to master") is per-*family*. The idea adds an explicit **difficulty rating on the individual geometry itself** - since 24.3's much larger geometry roster means a family could contain geometries of meaningfully different real-world difficulty, a per-geometry number (feeding into fixes-to-master, and potentially base defect risk or timer length at the stations that geometry passes through) would let the roster keep growing without every new geometry needing to awkwardly fit an existing family's one complexity level.

### 24.9 Reputation/familiarity can gate whether a customer will even offer a contract - and a way to actively earn access - THE OFFER/ACCEPT SCREEN ITSELF IS BUILT, THE FAMILIARITY-GATING HALF IS NOT

Beyond Section 8's existing Reputation-gates-which-tier-is-offered-at-all rule, the idea adds a per-contract-offer check: a customer asking for a **large quantity** of a geometry the player has **little or no familiarity with** might simply decline to offer that contract yet, rather than offering it and letting the player gamble on an oversized unfamiliar order. Two ways to clear that gate were raised: build up familiarity organically first (via a smaller order, or a related geometry per 24.5's carryover), or a more active **"start a conversation"** outreach action - a deliberate relationship-building step distinct from just completing contracts, that could unlock a customer's willingness to offer bigger/less-familiar work sooner. This is a new mechanic beyond Section 8's existing Relationship system (which only currently moves as a side effect of contract outcomes), not a reskin of it - "starting a conversation" implies a real player-initiated action with no obvious existing analog in the current systems.

**Built:** the foundational piece this whole subsection assumes - a genuine "Contract Offers" screen exists now (`GameData.contract_offers`, a pool the player browses and explicitly accepts via `accept_contract_offer()`, separate from `contracts`, the already-working list; an offer's deadline doesn't start until accepted). This also closes the previously-tracked "no player-facing choose which contract to accept" gap from the same day's earlier conversation. **Not built:** the familiarity-based decline (a customer simply not rolling an offer for a large unfamiliar ask) and the "start a conversation" outreach action - every currently-eligible tier/reputation combination can still roll any offer regardless of the player's familiarity with its geometries.

### 24.10 The open problem: displaying all of this without burying the player - RESOLVED FOR THE CORE CASE, VIA A REAL UI MOCKUP

Every idea above adds more information a contract or a part could carry - multiple line items per contract (24.1), a quality/speed score in progress (24.2), a per-geometry difficulty rating (24.8), per-geometry-pair familiarity (24.5) instead of one clean average, and a reason a contract isn't offered yet (24.9). The explicit concern raised: this is a lot of new information to surface without the Contracts view (or a future contract-offer screen) turning into a wall of numbers. No layout decision was made here on purpose - this needs its own dedicated UI design pass, most likely informed by mockups/ideas explored outside this codebase first (see the ChatGPT prompt starters below, offered in the same conversation this section documents) before any of it gets implemented.

**A mockup came back from exactly that external brainstorming (a ChatGPT-generated "Contract Offers" screen image) and was implemented directly**, adapted to this project's own 480x270 pixel-art chunky-panel style rather than the mockup's own dark sci-fi look: a collapsed row per offer (customer/payout/deadline/average familiarity) plus a pinned detail card for whichever one is selected - customer/tier header, a familiarity-derived risk badge ("MASTERED - SAFE CONTRACT" / "MODERATE RISK" / "UNFAMILIAR - HIGH RISK", from the *weakest* line item's familiarity, not the average, so one risky item can't hide behind easier ones on the same order), a tag line (complexity/alloy/"Investment Casting"/volume tier), a per-line-item list (placeholder icon, geometry, quantity, that specific geometry's own familiarity star rating), a footer risk-summary line, and an Accept button. Lives as a new "Offers" tab on the existing Contracts overlay (`scenes/contracts_overlay.gd`) alongside the original read-only "Active" list, rather than as a separate HUD button - see that file's own header comment for why (same lifecycle object, not "unrelated categories"). Per-pair familiarity carryover (24.5) and per-geometry difficulty (24.8) are still not built, so this screen currently shows the coarser existing numbers (per-family complexity, average/weakest familiarity) - it would only need richer data plugged in later, not a layout rework, once those two land.

### 24.11 Starter prompts for external UI brainstorming (e.g. ChatGPT/an image model)

Offered as a starting point, not a fixed spec - feel free to adapt before actually using one:

1. *"I'm designing a mobile idle/tycoon game about running an investment casting foundry (think Game Dev Tycoon's structure, but for manufacturing). I need a UI concept for a 'contract offers' screen on a 480x270-logical-resolution mobile layout. Each contract can have MULTIPLE line items (different part geometries, each with its own quantity), a customer name, a deadline, a payout, and a 'familiarity' rating per geometry (0-5 stars) that affects risk. Some contracts should visually read as 'risky/unfamiliar' vs 'safe/mastered.' Show me 3 distinct layout directions for one contract card in this list, optimized for a small mobile screen and a chunky pixel-art aesthetic."*
2. *"Design a compact 'part familiarity' indicator for a factory-management game, shown inline in a list of parts. Each part has FOUR separate familiarity sub-scores (one per production stage) that average into one star rating for a quick glance, but a player should be able to see the per-stage breakdown on demand (e.g. long-press). Propose a few compact visual treatments that fit in roughly 60x40 pixels at a glance, plus a expanded/detail state."*
3. *"I want a 'why can't I get this contract yet' UI moment for a tycoon game - a customer is willing to offer bigger contracts once the player is familiar enough with the part type, or if the player has built enough of a relationship with them. Show me some UI/UX concepts for communicating 'this contract is currently locked, here's what would unlock it' in an approachable, non-punishing way, for a small mobile screen."*
4. *"Suggest icon/silhouette concepts for a set of aerospace investment-casting part geometries for a pixel-art factory game: turbine blades, turbine vanes, blisks, recuperators, hot-section housings, seal rings, brackets, manifolds. Each should read as a distinct, recognizable silhouette even at a small size (roughly 32x32px), in a retro/chunky pixel-art style consistent with a Stardew-Valley-adjacent aesthetic, not photorealistic."*
5. *"I have a management-sim contract list where each contract can require several different part types with independent progress bars, all under one deadline. Propose a compact way to show 'contract-level' progress (all line items combined) alongside 'per-line-item' progress, without needing to expand every contract to see if it's on track."*
