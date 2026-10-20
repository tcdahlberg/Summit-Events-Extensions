# Amsterdam Community Sprint 2026 — AI Starter Kit

**October 19–20, 2026 | Amsterdam, Netherlands**

Welcome to the Summit Events App team at the Salesforce Community Sprint!

During this two-day Sprint, Salesforce community members collaborate to design, build, test, and document enhancements to the open-source Summit Events App.

You can contribute whether you're an Administrator, Developer, Architect, Consultant, Business Analyst, or nonprofit professional.

**Bring your own AI assistant!** This repository provides shared context so you can use ChatGPT, Claude, Gemini, GitHub Copilot, Cursor, or another LLM to support your work.

---

## 1. What are we building?

### The Annual Gala Challenge

Imagine you work for a nonprofit organization preparing its annual fundraising gala.

Your organization wants to invite **600 people**, including major donors, ambassadors, and other important stakeholders.

Salesforce already contains the Contacts and Leads you want to invite. Summit Events provides event management and registration functionality.

However, Summit Events does not currently provide the targeted invitation-management integration with Salesforce Campaigns described in our enhancement request.

**Our Sprint goal is to extend Summit Events with targeted invitation management using Salesforce Campaigns and Campaign Members.**

The proposed end-to-end process is:

1. Create a Summit Event and Event Instance.
2. Create a Salesforce Campaign linked to the Event Instance.
3. Select Contacts and Leads to invite.
4. Automatically create Summit Event Registrations for invitees.
5. Generate personalized invitation links.
6. Send invitations using Salesforce email capabilities or compatible marketing tools.
7. Allow invitees to register or decline.
8. Track invitations, responses, and registrations in Salesforce.

Not every feature is necessarily achievable during the two-day Sprint. We'll prioritize a working foundation, tested functionality, and documented next steps.

Read [Sprint Goals](SPRINT-GOALS.md) for the complete scenario, priorities, and intended outcomes.

## 2. Get familiar with Summit Events

The [Summit Events App](https://github.com/SFDO-Community/Summit-Events-App) is a free, open-source event management solution built for nonprofit and education organizations using Salesforce.

It supports capabilities such as event configuration, online registration, registration questions, appointments, fees, and confirmations.

Our work builds on the existing application rather than replacing it.

**Useful resources:**

- [Summit Events App — Official Repository](https://github.com/SFDO-Community/Summit-Events-App)
- [Summit Events Extensions — Sprint Repository](https://github.com/cmlcs/Summit-Events-Extensions)
- [Summit Events Application Overview](SUMMIT-EVENTS.md)
- [Sprint User Stories](USER-STORIES.md)

Before proposing changes, familiarize yourself with the existing application and identify which capabilities can be reused.

## 3. Set up your AI assistant

You are welcome to use your preferred AI assistant.

We have prepared a shared AI Context Pack containing the information your assistant needs to understand our project.

| File | Purpose |
|---|---|
| [SPRINT-GOALS.md](SPRINT-GOALS.md) | Business scenario, objectives, and expected outcomes |
| [SUMMIT-EVENTS.md](SUMMIT-EVENTS.md) | Existing application and technical context |
| [USER-STORIES.md](USER-STORIES.md) | Proposed functionality and acceptance criteria |
| [SPRINT-DECISIONS.md](SPRINT-DECISIONS.md) | Architectural decisions and open questions |
| [AGENTS.md](../../AGENTS.md) | Instructions for AI coding and reasoning assistants |

### Option A — ChatGPT, Claude, or Gemini

1. Create a new Project or dedicated conversation in your AI assistant.
2. Upload the five context files listed above, or provide their contents.
3. Paste the initialization prompt below.
4. Ask your assistant to summarize the Sprint objectives.
5. Start working on your assigned user story.

Some AI tools support Projects with persistent knowledge, while others require uploading documents to each conversation.

### Option B — GitHub Copilot, Cursor, or Claude Code

1. Clone your fork of the Sprint repository.
2. Open the repository in your preferred development environment.
3. Configure your assistant to use the repository instructions in `AGENTS.md`.
4. Read the Sprint documentation.
5. Ask the assistant to inspect the actual source code before suggesting changes.

Different coding assistants discover project instructions differently. Check your tool's documentation to confirm that the instructions are being loaded.

### AI Initialization Prompt

Copy the following prompt into your AI assistant:

You are my Salesforce solution design and development assistant for the Amsterdam Community Sprint, October 19–20, 2026.

## Project

We are working on enhancements to the open-source Summit Events App.

**Original application repository:**
https://github.com/SFDO-Community/Summit-Events-App

**Amsterdam Sprint development repository:**
https://github.com/cmlcs/Summit-Events-Extensions

The original repository contains the existing Summit Events application. The Sprint repository is our collaborative workspace for enhancements, documentation, and user stories.

## Sprint Objective

Extend Summit Events to support targeted event invitations using Salesforce Campaigns and Campaign Members.

Our business scenario is a nonprofit annual fundraising gala with 600 invitees, including major donors, ambassadors, and other stakeholders.

## Your Responsibilities

1. Read the supplied Sprint documentation to understand our objectives, requirements, and user stories.
2. Use the original Summit Events repository to understand existing functionality and architecture.
3. Use the Sprint repository to understand our proposed enhancements, implementation decisions, and ongoing work.
4. Distinguish between existing functionality, proposed enhancements, assumptions, and unresolved questions.
5. Never invent Salesforce objects, fields, Apex classes, methods, or existing functionality.
6. Favor standard Salesforce capabilities where practical.
7. Consider security, scalability, bulk processing, testing, and maintainability.
8. Help me analyze requirements, design solutions, implement changes, test functionality, and produce documentation.
9. Verify technical recommendations against actual source code whenever possible.
10. Follow the development guidelines in `AGENTS.md`.

## Getting Started

First, review the available Sprint context and repository information.

Then explain:

1. What the Summit Events App currently does.
2. What the Amsterdam Sprint aims to deliver.
3. Which technical details need further investigation.
4. How you can help me contribute to my assigned user stories.

If you cannot access the repositories directly, tell me which files or source-code sections you need. Do not claim to have inspected code you haven't accessed.

## 4. Choose how you want to contribute

You don't need to be a developer to make a meaningful contribution.

| Interest or skill | Possible contributions |
|---|---|
| Salesforce Administration | Campaign configuration, Flow, page layouts, testing |
| Business Analysis | User stories, acceptance criteria, business process design |
| Salesforce Development | Apex, Lightning Web Components, integrations |
| Solution Architecture | Data model, security, scalability, solution design |
| Marketing and Fundraising | Invitation strategy, segmentation, communication journeys |
| Quality Assurance | Functional testing, regression testing, test scenarios |
| Documentation | User guides, technical documentation, screenshots, videos |
| DevOps and GitHub | Branches, pull requests, automated tests, code reviews |

Review [User Stories](USER-STORIES.md) and coordinate with the team before starting work.

If you're unsure where to contribute, ask your AI assistant:

> Based on the Sprint user stories and my experience as a Salesforce Administrator, suggest three tasks I could contribute to during the Sprint. Explain the expected deliverables and skills needed.

Replace "Salesforce Administrator" with your own role or experience.

## 5. Contribute using GitHub

We use GitHub to collaborate and review changes.

**Sprint repository:** [cmlcs/Summit-Events-Extensions](https://github.com/cmlcs/Summit-Events-Extensions)

### Step 1 — Fork the repository

Open the Sprint repository and select **Fork** to create a copy under your GitHub account.

If you already have Write access, you may work directly in a feature branch of the Sprint repository instead.

### Step 2 — Clone your fork

```bash
git clone https://github.com/YOUR-USERNAME/Summit-Events-Extensions.git
cd Summit-Events-Extensions
```

Replace `YOUR-USERNAME` with your GitHub username.

### Step 3 — Create a feature branch

```bash
git checkout -b feature/US-03-registration-automation
```

Use a descriptive branch name associated with your assigned user story.

### Step 4 — Implement and test

Work on your assigned task, using your AI assistant where helpful.

Test your changes and document any assumptions, limitations, or dependencies.

### Step 5 — Commit and push

```bash
git add .
git commit -m "US-03: Implement registration automation"
git push -u origin feature/US-03-registration-automation
```

### Step 6 — Create a pull request

Open a pull request targeting the Sprint repository's `main` branch.

Include:

- User story reference
- Summary of changes
- Testing performed and results
- Screenshots or demonstrations where useful
- Known issues or limitations

Do not merge your own changes without following the team's review process.

## 6. Working with AI responsibly

AI assistants can help us work faster, but they can also generate incorrect or insecure solutions.

Please follow these principles:

**Verify before implementing.** Check that objects, fields, methods, and components actually exist in the relevant Salesforce implementation.

**Understand what you contribute.** Be prepared to explain AI-generated code or configuration to another participant.

**Protect data and credentials.** Do not upload real donor information, Salesforce credentials, access tokens, private keys, or confidential organizational data to AI services.

**Test your work.** AI-generated code and configuration require the same testing and review as manually written contributions.

**Respect existing architecture.** Prefer reusing established patterns rather than introducing unnecessary components.

**Document your decisions.** Significant architectural choices should be recorded in [Sprint Decisions](SPRINT-DECISIONS.md).

## 7. Collaborate during the Sprint

This is a community effort, not a competition between individuals or AI tools.

We encourage you to:

- Work together on user stories.
- Ask questions and share discoveries.
- Review one another's work.
- Help participants who are new to GitHub or Salesforce development.
- Share useful AI prompts and techniques.
- Document lessons learned for future contributors.

Use the designated Sprint Slack channel for questions, coordination, and progress updates.

Before beginning a user story, check whether someone else is already working on it.

## 8. What does success look like?

By the end of the Sprint, we aim to have:

- A shared understanding of the invitation-management requirements.
- Agreed solution architecture and documented design decisions.
- Working, demonstrable enhancements where feasible.
- Tested changes submitted through pull requests.
- Updated user and technical documentation.
- A prioritized backlog of remaining work.

A completed design, a well-tested Flow, an improved user story, or a useful piece of documentation can all be valuable Sprint contributions.

Not every user story needs to be completed in two days.

## 9. Getting started — Your first 10 minutes

- [ ] Open the Sprint GitHub repository.
- [ ] Read the Sprint Goals.
- [ ] Review the Summit Events application overview.
- [ ] Import the AI Context Pack into your preferred assistant.
- [ ] Ask your assistant to summarize the project.
- [ ] Review the available user stories.
- [ ] Choose a task and coordinate with your team.
- [ ] Start contributing!

---

**Build together. Learn together. Contribute back to the Salesforce community.**

*Amsterdam Salesforce Community Sprint — October 19–20, 2026*
