<!-- Source: https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/ -- fetched 2026-11-16 via curl, converted with a stdlib HTML->MD script. Code blocks verbatim. -->

[Press](https://blog.reactive.network/tag/press/)

# Reactive Omni Buildathon: Thirty Days to Find Out What One Second Buys
   [ ![Reactive Network](/content/images/size/w160/2025/08/Symbol_ColorBlack_H32--1--1.png) ](/author/dave/)

#### [Reactive Network](/author/dave/)
  Nov 4, 2026 — 4 min read     ![Reactive Omni Buildathon: Thirty Days to Find Out What One Second Buys](/content/images/size/w1200/2026/11/main--1-.jpg)

Reactive Omni has been live on mainnet since October 28th. Starting tomorrow, November 5th, we're opening it up to builders: Reactive Omni Buildathon runs until **December 5th**, with **$5,500 in prizes, paid in REACT**, across three tracks. Registration and submissions run through[ DoraHacks](https://dorahacks.io/hackathon/reactive-omni-buildathon?ref=blog.reactive.network).

## Short Version for Newcomers

A reactive contract is an "if this happens there, do that here" rule that lives on-chain. It watches for events on other blockchains, like a price moving or a deposit landing, and responds by sending a transaction wherever it's needed. Nobody has to keep a bot running to watch for the event.

Omni is the new version of Reactive Network. It's faster, and the buildathon is about seeing what that speed makes possible. You can join whether you write Solidity daily or have never deployed a contract.

# Why Speed Changes the Menu

On the previous version of Reactive Network, blocks came every **~7 seconds**. For a lot of automation that was fine, since a rebalancing rule or a notification doesn't care about a few seconds. But it ruled out anything where a few seconds decide the outcome, like catching a price gap before it closes.

Reactive Omni runs on **CometBFT consensus**, with **~1s blocks** and **instant finality**. Once a block is committed, it's final, with no waiting for confirmations to pile up. We covered why we chose that path in[ Finality Wars](https://blog.reactive.network/finality-wars-counting-validators-counts-wrong/). Now we want to see what builders do with it.

Some ideas that didn't fit in seven seconds should fit in one. Which ones? That's what the next month is for.

# Three Tracks

## Every Second Counts

This track is for DeFi where reaction time matters, built on **Unichain Sepolia**, **Base Sepolia**, or both, with Reactive's Lasna testnet in the middle. Both chains are fast: Unichain Sepolia produces **1s blocks**, and Base Sepolia, since its Denim upgrade, produces **200ms blocks**. Every loop runs from an event, through Reactive, to a callback, and the full loop is what users feel.

Think arbitrage on price gaps between pools, stop-loss and take-profit orders for DEX positions, vaults that rebalance as conditions shift, or withdrawal queues that settle the moment they can. The strongest entries will show their latency numbers measured across the full loop, not just one leg of it.

## Set It and Forget It

This track is for personal automations anyone can build, on any chain Reactive supports. AI coding tools have made it realistic for people who've never written a contract to build one that does something useful for them. Think of a portfolio tracker, an alert when a liquidity position hits a price, or custom rebalancing rules.

Speed matters less here than usefulness. The question to ask is simple: is this something you'd actually leave running?

## Reactive Meets AI

This track is deliberately open. Bring a neural network into the loop and show us how it works alongside Reactive. A model could decide what a reactive contract does next, interpret the events it picks up, or be triggered by them.

There's one rule: the AI has to be part of the running system, not just the tool you used to write the code. Projects where AI only helped you build belong in **Set It and Forget It**.

We don't know yet what the most interesting combination of event-driven contracts and models looks like. Maybe you do.

# Prizes

Prizes are denominated in USD and paid in REACT.

- **Every Second Counts:** $2,000 for the first place, $250 for the runner-up
- **Set It and Forget It:** $2,000 for the first place, $250 for the runner-up
- **Reactive Meets AI:** $1,000 for first place

# How Judging Works

Every entry is scored from 1 to 5 on four equally weighted criteria:

- **Execution:** Does it run? We want to see the reactive transactions and the callbacks they trigger on-chain. Entries without them aren't scored further.
- **Integration:** Does the reactive contract do real work, or is it bolted on?
- **Usefulness:** Does it solve a problem real users have?
- **Craft:** Readable code, a working demo, and documentation someone else could follow.

Entries are judged by Reactive team. We'll announce any guest judges on the [DoraHacks](https://dorahacks.io/hackathon/reactive-omni-buildathon/detail?ref=blog.reactive.network) page.

# Getting Started

Register on[ DoraHacks](https://dorahacks.io/hackathon/reactive-omni-buildathon?ref=blog.reactive.network) and pick a track. When you submit, include a link to your public repository, your deployed contract addresses, a few transaction hashes showing the full loop from origin event to callback, and a demo video under three minutes.

A few ground rules:

- **Every Second Counts** runs on Lasna testnet. The other two tracks can use Reactive mainnet or Lasna.
- Repositories need to be public and open-source by the time you submit.
- Everything should be built during the event. Prior work can come in as a dependency, but not as the submission itself.
- On Base Sepolia, use timestamps rather than block counts for timers, cooldowns, or deadlines. Blocks now arrive every **200ms**, so block-based timers run ten times faster than they used to.

Testnet REACT is available from[ Reactive Lasna faucet](https://dev.reactive.network/reactive-mainnet?ref=blog.reactive.network#get-testnet-react). [Reactive docs](https://dev.reactive.network/?ref=blog.reactive.network) cover everything from your first contract onward, and the full lists of[ mainnet](https://dev.reactive.network/origins-and-destinations?ref=blog.reactive.network#mainnet-chains) and[ testnet](https://dev.reactive.network/origins-and-destinations?ref=blog.reactive.network#testnet-chains) chains show where you can build.

We built Omni so reactive contracts could keep up with the chains they watch. Now it's your turn to show us what they can do in a second. Good luck, and make every second count!

# About Reactive Network

Reactive Network is an EVM automation layer built around reactive contracts — event-driven smart contracts for cross-chain execution. It runs on CometBFT consensus, providing deterministic finality with roughly one-second block times while maintaining full EVM compatibility. Reactive contracts subscribe to event logs across EVM chains and execute Solidity logic automatically when matching events occur, issuing cross-chain callback transactions when their conditions are met.

[Website](https://reactive.network/?ref=blog.reactive.network) | [Blog](https://blog.reactive.network/) | [X](https://x.com/0xreactive?ref=blog.reactive.network) | [Telegram](https://t.me/Reactive_Network?ref=blog.reactive.network) | [Discord](https://discord.com/invite/SaZAfkgZhj?ref=blog.reactive.network) | [Docs](https://dev.reactive.network/?ref=blog.reactive.network)

**Build once — react everywhere!**

## Read more
   [  ![Reactive Circuit: Incentive Program For Working Integrations](/content/images/size/w600/2026/10/Reactive-Circuit.png)

### Reactive Circuit: Incentive Program For Working Integrations

Over the past two years we have run a hackathon, a mainnet build campaign, and three bounty sprints. Judging all of them taught us what a good reactive integration looks like: it fits the project it sits in, it beats the alternatives a team could have reached for, and it   ](/reactive-circuit-incentive-program-for-working-integrations/)   [  ![Reactive Mainnet: Migration Complete](/content/images/size/w600/2026/10/Migration-Complete.jpg)

### Reactive Mainnet: Migration Complete

Migration is complete. Reactive Mainnet is now running on the Omni fork. What's Different Mainnet gets the same upgrade Lasna got on October 7th. The biggest change is that the RVM is gone. Reactive contracts now deploy once, to a single environment, as standard Solidity targeting version 0.   ](/reactive-mainnet-migration-complete/)   [  ![Reactive Delegation](/content/images/size/w600/2026/10/delegation-main.jpg)

### Reactive Delegation

A blockchain is only as trustworthy as the people keeping it running. With Reactive Network’s move to CometBFT consensus, that job falls to validators and the REACT holders who back them. Delegation is how any REACT holder can take part. You don’t need to run a node: back   ](/reactive-delegation/)   [  ![Reactive Network: Towards the New Mainnet](/content/images/size/w600/2026/10/Towards-Mainnet.jpg)

### Reactive Network: Towards the New Mainnet

Heads up: Reactive Mainnet goes offline for migration on Wednesday, October 28th, at 12:00 UTC. Why Pause? On October 7th, Lasna testnet completed its migration to the Omni fork. Now it's mainnet's turn: Reactive Mainnet is leaving the legacy Geth and Prysm stack and moving   ](/reactive-network-towards-the-new-mainnet/)   [  ![Reactive Staking: Season 10](/content/images/size/w600/2026/10/staking-10.jpg)

### Reactive Staking: Season 10

Reactive Staking Season 9 closes at block 7,196,129 on Wednesday, October 14th, and its one-month pool expires with it. Season 10 picks up on the very next block with a two-week pool that runs until the Omni upgrade goes live on Reactive mainnet on October 28th.   ](/reactive-staking-season-10/)   [  ![Reactive x Robinhood: Chain Integration](/content/images/size/w600/2026/09/reactive-robinhood.jpg)

### Reactive x Robinhood: Chain Integration

Reactive integrates with Robinhood Chain, an Ethereum Layer-2 built for tokenized real-world assets, as both an origin and a destination chain within Reactive Network. Stock Tokens and the DeFi built around them already trade around the clock. With Reactive, the logic that manages them can run around the   ](/reactivexrobinhood/)   [  ![Lasna Testnet Completes Migration to Omni Fork](/content/images/size/w600/2026/10/Wednesday.jpg)

### Lasna Testnet Completes Migration to Omni Fork

Migration is complete. Lasna is now running on the Omni fork. What's Different The biggest change is that the RVM is gone. Reactive contracts now deploy once, to a single environment, as standard Solidity targeting version 0.8.29, and dual deployment is a thing of the past.   ](/lasna-testnet-completes-migration-to-omni-fork/)   [  ![Lasna Testnet Pauses for Migration](/content/images/size/w600/2026/10/Monday.jpg)

### Lasna Testnet Pauses for Migration

Heads up: Lasna goes offline for migration on Wednesday, October 7th, at 12:00 UTC. Why Pause? Back on May 26th, we announced the launch of a new version of Lasna testnet, running on our new CometBFT-based architecture. Now, in preparation for our mainnet migration, the original Lasna testnet,   ](/lasna-testnet-pauses-for-migration/)
