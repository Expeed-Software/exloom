# Failure Modes — designing-ui

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


### "I'll match the existing design later"

**The thought:** "Let me get the functionality working first, then I'll make it look consistent."

**Why it feels right:** Functionality is the hard part. Styling is just CSS — easy to change later.

**What actually happens:** "Later" never comes. The inconsistent UI ships. Now you have a 16th shade of blue and a button that's 2px taller than every other button. Every subsequent developer copies your inconsistency because they think it was intentional.

**Fix:** Do the three-screen audit before writing any component code. Extract the tokens first. Build with the right values from the start — it takes the same amount of time as building with wrong values.

### "The existing UI is bad, I'll do it better"

**The thought:** "These screens look dated. My new page will use modern patterns and better spacing."

**Why it feels right:** You have better taste. The existing UI was built under time pressure. Yours will be better.

**What actually happens:** Your page looks great in isolation. In the product, it looks like it was built by a different company. Users distrust it. The team now has two visual styles to maintain. Nobody knows which one is "right."

**Fix:** Match first, improve later. If the existing UI genuinely needs improvement, propose a visual refresh as a separate task that updates everything together. Don't unilaterally modernize one page.

### "I don't need to check accessibility for an internal tool"

**The thought:** "Only 50 people use this. None of them are visually impaired."

**Why it feels right:** Accessibility feels like overhead for a small internal audience.

**What actually happens:** A team member with RSI can't use keyboard navigation. A colorblind developer can't distinguish error states from success states. Someone using a large monitor can't read 12px gray-on-light-gray text. Accessibility isn't just screen readers — it's everyone.

**Fix:** Run axe-core. It takes 30 seconds. Fix the violations. This is the floor, not the ceiling.

### "We need a design system before we can build more UI"

**The thought:** "We keep building inconsistent UI. We need to stop feature work and build a design system first."

**Why it feels right:** A design system would solve the consistency problem once and for all.

**What actually happens:** The team spends 3 months building a component library that nobody uses because it doesn't match what they actually need. Features are delayed. The design system becomes stale because it was built in a vacuum.

**Fix:** Extract, don't invent. Ship features. When you see duplication, extract it. When the extracted components pile up, that's your design system. It matches what you actually build because it came from what you actually built.

### "A component library means I can skip the design work"

**The thought:** "We use Angular Material (or PrimeNG, Material UI, Ant) — drop the components in and design takes care of itself."

**Why it feels right:** Professional components, accessibility handled, looks good immediately. And if your org standardizes on one library, using it genuinely *is* the right call — that's the convention.

**What actually happens — two failure shapes:**
- **Un-themed adoption.** You use the library with its default theme, so your product looks like every other un-themed Material app: generic, identity-less, "obviously a Material site." The library was supposed to be a foundation, not the finished look.
- **Library sprawl.** You reach for a second component library because one widget was easier there, and now the product mixes two visual languages, doubles the bundle, and fractures the token system.

**Fix:** The work isn't avoiding the component library — it's *theming the one you have*. Configure its token/theme layer to your product's colors, spacing, and typography (Angular Material's theming API, PrimeNG's design tokens, the library's theme config) and extend that single library rather than bolting a second one alongside it. A component library plus a deliberately configured theme **is** your design system — that's exactly what the worked example above does. What you must not do is ship it raw and un-themed, or stack libraries.
