# Worked Example: Adding a User Settings Page to an Existing Angular Tool — designing-ui

Extracted from SKILL.md so the skill loads lean.


**Context:** The team is adding a user settings page to an internal Angular tool that already has a dashboard, a list view, and a detail view. No formal design system. No designer on the team. The stack is Angular 17 with Angular Material and SCSS — the common shape for this org.

### Design Thinking

> **Purpose:** Let users update their notification preferences and profile info. One thing to accomplish: change a setting and confirm it saved.
>
> **Tone:** Match existing — the tool is industrial/technical. Dense data tables, muted grays, a single accent color.
>
> **Constraints:** Angular 17 + Angular Material + SCSS. Must work on laptop screens (1280px+). No mobile requirement for this internal tool. Must follow the existing `mat-sidenav` shell.
>
> **Differentiation:** Not needed — this is an internal tool. Consistency with existing pages is the goal, not novelty.

### Three-Screen Audit

Screenshots of: Dashboard, Users List, User Detail.

Findings (read from `styles/_theme.scss` and the existing component stylesheets, not guessed):
- **Colors:** the project defines a Material theme — primary `$accent: #3b82f6`, surface `#ffffff`, app background `#f1f5f9`, text `#1e293b`. These are SCSS variables in `styles/_tokens.scss`, not ad-hoc hex.
- **Spacing:** an 8px scale via a `spacing()` SCSS function (`spacing(2)` = 16px) used consistently.
- **Typography:** Material typography config; page titles use the `headline-6` level, body uses `body-2`.
- **Components:** `mat-card` for containers, `mat-table` for lists, `mat-raised-button color="primary"` for primary actions.
- **Tone:** Clean, dense, professional. No playfulness.

### Implementation Decision

No new visual primitives needed. The settings page reuses `mat-card`, Material form fields matching the existing forms, and `mat-raised-button` for actions. The only new pattern is a `mat-tab-group` for "Profile" vs "Notifications" — already part of Angular Material, so it inherits the theme automatically. No new colors, spacing values, or typography levels introduced; everything references the existing SCSS tokens and Material theme.

### Accessibility Check

- Material form fields use `<mat-label>`, which wires the label to the input automatically
- `mat-tab-group` provides keyboard navigation and ARIA tab roles out of the box; verified the focus indicator is visible against the theme
- Save confirmation uses `MatSnackBar` with an `aria-live` region; the success/error distinction includes an icon, not color alone
- Save button uses `[disabled]` during submission and announces busy state

### Result

The settings page is indistinguishable from the rest of the tool in visual quality. It introduced zero new tokens — it consumed the existing Material theme and SCSS variables. The team didn't need a designer or a design system; they needed to read what already existed and stay inside it.
